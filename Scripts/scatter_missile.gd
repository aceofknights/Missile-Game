extends Area2D

signal enemy_died

# NOTE: explosion_scene kept here only so you don't break inspector refs,
# but we will NOT use it for scatter anymore.
@export var explosion_scene: PackedScene
@export var child_missile_scene: PackedScene

# PATCH: split after 1 second of travel
@export var split_delay := 1.0
@export var speed := 140.0

# Optional: control spread by offsets OR by angle; this keeps your old offset approach.
@export var split_offsets := [-140.0, 0.0, 140.0]

var velocity := Vector2.ZERO
var is_dying := false
var has_split := false

@onready var split_timer: Timer = $SplitTimer


func _ready():
	add_to_group("enemy")
	rotation = velocity.angle()
	connect("area_entered", Callable(self, "_on_area_entered"))

	split_timer.one_shot = true # PATCH: ensure it only fires once
	split_timer.wait_time = split_delay
	split_timer.timeout.connect(_on_split_timer_timeout)
	split_timer.start()


func _process(delta):
	position += velocity * speed * delta

	# If it reaches the bottom before splitting, just remove it (no explosion),
	# but still spawn children from that point (same behavior as "death point").
	if position.y >= get_viewport_rect().size.y:
		_split_and_remove()


func _on_area_entered(area):
	if area.is_in_group("building"):
		area.queue_free()
		# PATCH: on hit, split from impact point (no explosion)
		_split_and_remove()


func _on_split_timer_timeout():
	# PATCH: split after delay, no explosion
	_split_and_remove()


# PATCH: unified "death" for scatter = split + remove, no explosion, no rewards
func _split_and_remove():
	if is_dying or has_split:
		return

	is_dying = true
	has_split = true

	split_into_children()

	# IMPORTANT: keep enemy counting consistent
	emit_signal("enemy_died")

	queue_free()


func split_into_children():
	if child_missile_scene == null:
		return

	var viewport = get_viewport_rect().size

	# Spawn three normal missiles from this exact point
	var base_target_x = clamp(global_position.x, 120.0, viewport.x - 120.0)

	for offset in split_offsets:
		var child = child_missile_scene.instantiate()

		# keep your enemies_alive accounting consistent
		GameManager.enemies_alive += 1
		child.connect("enemy_died", Callable(GameManager, "_on_enemy_died"))

		child.global_position = global_position

		# Aim children downward toward the ground with spread in X
		var target = Vector2(
			clamp(base_target_x + float(offset), 40.0, viewport.x - 40.0),
			viewport.y
		)

		# Your normal missile expects `velocity` (like your boss spawner sets)
		child.velocity = (target - global_position).normalized()

		get_tree().current_scene.add_child(child)
