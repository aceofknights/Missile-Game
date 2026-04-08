extends Area2D

signal clone_destroyed(clone: Area2D)

@export var missile_scene: PackedScene
@export var fire_interval: float = 3.5
@export var move_speed: float = 260.0
@export var active_tint: Color = Color(1.0, 0.55, 0.95, 1.0)
@export var inactive_tint: Color = Color(0.75, 0.82, 1.0, 0.92)

@onready var fire_timer: Timer = get_node_or_null("FireTimer")
@onready var sprite: CanvasItem = get_node_or_null("Sprite2D") as CanvasItem

var firing_enabled: bool = false
var is_dying: bool = false
var move_target: Vector2 = Vector2.ZERO
var _moving: bool = false
var _is_active_shooter: bool = false


func _ready() -> void:
	add_to_group("enemy")
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)

	if fire_timer == null:
		push_error("Clone scene is missing FireTimer")
		return

	fire_timer.wait_time = fire_interval
	fire_timer.timeout.connect(_on_fire_timer_timeout)
	_apply_visual_state()


func begin_clone_phase(start_pos: Vector2, _unused_angle: float, can_fire: bool) -> void:
	global_position = start_pos
	move_target = start_pos
	_moving = false
	firing_enabled = can_fire
	_is_active_shooter = false

	if fire_timer:
		fire_timer.stop()

	_apply_visual_state()


func set_move_target(target: Vector2, speed_override: float = 260.0) -> void:
	move_target = target
	move_speed = speed_override
	_moving = true


func set_firing_enabled(enabled: bool) -> void:
	firing_enabled = enabled
	if not firing_enabled and fire_timer:
		fire_timer.stop()


func set_active_shooter(active: bool) -> void:
	_is_active_shooter = active
	_apply_visual_state()


func fire_attack_now() -> void:
	if not firing_enabled:
		return
	if not _is_active_shooter:
		return
	if _moving:
		return
	_spawn_normal_missile()


func _process(delta: float) -> void:
	if is_dying:
		return

	if _moving:
		global_position = global_position.move_toward(move_target, move_speed * delta)
		if global_position.distance_to(move_target) <= 4.0:
			_moving = false


func _on_area_entered(area: Area2D) -> void:
	if is_dying:
		return

	if area.name == "Projectile":
		area.queue_free()
		_destroy_clone()
		return

	if area.name == "Explosion":
		_destroy_clone()
		return

	if area.is_in_group("defense_target"):
		if area.has_method("die"):
			area.call_deferred("die")
		else:
			area.queue_free()
		_destroy_clone()


func _destroy_clone() -> void:
	if is_dying:
		return

	is_dying = true

	if fire_timer:
		fire_timer.stop()

	monitoring = false
	monitorable = false

	emit_signal("clone_destroyed", self)
	queue_free()


func _on_fire_timer_timeout() -> void:
	pass


func _spawn_normal_missile() -> void:
	if missile_scene == null:
		return

	var missile = missile_scene.instantiate()
	GameManager.enemies_alive += 1
	missile.connect("enemy_died", Callable(GameManager, "_on_enemy_died"))

	var viewport: Vector2 = get_viewport_rect().size
	var target: Vector2 = Vector2(randf_range(40.0, viewport.x - 40.0), viewport.y)
	missile.global_position = global_position + Vector2(0, 24)
	missile.velocity = (target - missile.global_position).normalized()
	get_tree().current_scene.add_child(missile)


func _apply_visual_state() -> void:
	if sprite == null:
		return

	sprite.modulate = active_tint if _is_active_shooter else inactive_tint
