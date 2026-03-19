extends Area2D

signal enemy_died

@export var explosion_scene: PackedScene
@export var child_missile_scene: PackedScene
@export var split_delay := 1.0
@export var speed := 140.0
@export var split_offsets := [-140.0, 0.0, 140.0]

var velocity := Vector2.ZERO
var is_dying := false
var has_split := false

@onready var split_timer: Timer = $SplitTimer


func _ready() -> void:
	add_to_group("enemy")
	rotation = velocity.angle()
	connect("area_entered", Callable(self, "_on_area_entered"))

	split_timer.one_shot = true
	split_timer.wait_time = split_delay
	split_timer.timeout.connect(_on_split_timer_timeout)
	split_timer.start()


func _process(delta: float) -> void:
	var zone_multiplier := IonFieldUtils.get_speed_multiplier_at(global_position, false)
	position += velocity * speed * zone_multiplier * delta

	if position.y >= get_viewport_rect().size.y:
		_split_and_remove()


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("building"):
		area.queue_free()
		_split_and_remove()


func _on_split_timer_timeout() -> void:
	_split_and_remove()


func _split_and_remove() -> void:
	if is_dying or has_split:
		return

	is_dying = true
	has_split = true
	split_into_children()
	emit_signal("enemy_died")
	queue_free()


func split_into_children() -> void:
	if child_missile_scene == null:
		return

	var viewport = get_viewport_rect().size
	var base_target_x = clamp(global_position.x, 120.0, viewport.x - 120.0)

	for offset in split_offsets:
		var child = child_missile_scene.instantiate()
		GameManager.enemies_alive += 1
		child.connect("enemy_died", Callable(GameManager, "_on_enemy_died"))
		child.global_position = global_position

		var target = Vector2(
			clamp(base_target_x + float(offset), 40.0, viewport.x - 40.0),
			viewport.y
		)
		child.velocity = (target - global_position).normalized()
		get_tree().current_scene.add_child(child)
