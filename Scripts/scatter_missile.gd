extends Area2D

signal enemy_died

@export var explosion_scene: PackedScene
@export var child_missile_scene: PackedScene
@export var split_delay := 2.5
@export var speed := 140.0

var velocity := Vector2.ZERO
var is_dying := false
var has_split := false

@onready var split_timer: Timer = $SplitTimer


func _ready():
	add_to_group("enemy")
	rotation = velocity.angle()
	connect("area_entered", Callable(self, "_on_area_entered"))
	split_timer.wait_time = split_delay
	split_timer.timeout.connect(_on_split_timer_timeout)
	split_timer.start()


func _process(delta):
	position += velocity * speed * delta

	if position.y >= get_viewport_rect().size.y:
		die(true)


func _on_area_entered(area):
	if area.is_in_group("building"):
		area.queue_free()
		die(true)


func _on_split_timer_timeout():
	if is_dying or has_split:
		return

	has_split = true
	split_into_children()
	die(true)


func split_into_children():
	if child_missile_scene == null:
		return

	var viewport = get_viewport_rect().size
	var base_target_x = clamp(global_position.x, 120.0, viewport.x - 120.0)
	var offsets = [-140.0, 0.0, 140.0]

	for offset in offsets:
		var child = child_missile_scene.instantiate()
		GameManager.enemies_alive += 1
		child.connect("enemy_died", Callable(GameManager, "_on_enemy_died"))
		child.global_position = global_position

		var target = Vector2(clamp(base_target_x + offset, 40.0, viewport.x - 40.0), viewport.y)
		child.velocity = (target - global_position).normalized()
		get_tree().current_scene.add_child(child)


func die(no_reward := false):
	if is_dying:
		return
	is_dying = true

	if not no_reward:
		GameManager.add_resources(2)

	emit_signal("enemy_died")

	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		explosion.gives_reward = not no_reward
		get_tree().current_scene.add_child(explosion)

	queue_free()
