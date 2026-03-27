extends Area2D

signal plane_removed(plane: Area2D)

@export var role := "fighter"
@export var missile_scene: PackedScene
@export var explosion_scene: PackedScene
@export var fighter_projectile_scene: PackedScene
@export var base_speed := 120.0
@export var action_interval := 2.0
@export var base_accuracy := 0.9
@export var min_accuracy := 0.35
@export var accuracy_decay_per_second := 0.12
@export var fighter_texture: Texture2D
@export var bomber_texture: Texture2D
@export var fighter_scale: Vector2 = Vector2(1, 1)
@export var bomber_scale: Vector2 = Vector2(1, 1)
@export var fighter_color: Color = Color()
@export var bomber_color: Color = Color()

@onready var action_timer: Timer = $ActionTimer
@onready var sprite: Sprite2D = $Sprite2D

var direction := Vector2.RIGHT
var speed_multiplier := 1.0
var accuracy_multiplier := 1.0
var _is_dead := false


func _ready() -> void:
	add_to_group("enemy")
	monitoring = true
	monitorable = true
	connect("area_entered", Callable(self, "_on_area_entered"))

	action_timer.wait_time = action_interval
	action_timer.timeout.connect(_on_action_timer_timeout)
	action_timer.start()

	_apply_role_visuals()


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

	if role == "fighter":
		accuracy_multiplier = max(min_accuracy, accuracy_multiplier - (accuracy_decay_per_second * delta))

	var viewport = get_viewport_rect().size
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


func set_speed_multiplier(multiplier: float) -> void:
	speed_multiplier = max(0.2, multiplier)


func reset_accuracy() -> void:
	accuracy_multiplier = 1.0


func _on_action_timer_timeout() -> void:
	if _is_dead:
		return
	if role == "fighter":
		_fire_intercept()
	else:
		_drop_bomb()


func _fire_intercept() -> void:
	if fighter_projectile_scene == null:
		return

	var projectiles = get_tree().get_nodes_in_group("projectile")
	if projectiles.is_empty():
		return
	var projectile: Area2D = projectiles[randi() % projectiles.size()]
	if not is_instance_valid(projectile):
		return

	var hit_chance = clamp(base_accuracy * accuracy_multiplier, min_accuracy, 0.98)
	if randf() > hit_chance:
		return

	var shot = fighter_projectile_scene.instantiate()
	shot.global_position = global_position + Vector2(0, 8)
	shot.target_node = projectile
	shot.target_position = projectile.global_position
	get_tree().current_scene.add_child(shot)


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
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		explosion.gives_reward = false
		get_tree().current_scene.add_child(explosion)

	emit_signal("plane_removed", self)
	queue_free()
