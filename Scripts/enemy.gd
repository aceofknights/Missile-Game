extends Area2D

@export var explosion_scene: PackedScene
@export var speed := 100.0

signal enemy_died

var velocity := Vector2.ZERO
var is_dying := false


func _ready() -> void:
	rotation = velocity.angle()
	connect("area_entered", Callable(self, "_on_area_entered"))
	add_to_group("enemy")


func _process(delta: float) -> void:
	var zone_multiplier := IonFieldUtils.get_speed_multiplier_at(global_position, false)
	position += velocity * speed * zone_multiplier * delta

	if position.y >= get_viewport_rect().size.y:
		die(true)


func _on_area_entered(area: Area2D) -> void:
	if area.name == "Projectile":
		die(false)
		area.queue_free()
	elif area.is_in_group("defense_target"):
		if area.has_method("die"):
			area.call_deferred("die")
		else:
			area.queue_free()
		die(true)


func die(no_reward := false) -> void:
	if is_dying:
		return
	is_dying = true

	if not no_reward:
		GameManager.add_resources(1)

	emit_signal("enemy_died")

	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		explosion.gives_reward = not no_reward
		get_tree().current_scene.add_child(explosion)

	queue_free()
