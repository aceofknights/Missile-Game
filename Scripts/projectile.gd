extends Area2D

@export var explosion_scene: PackedScene
@export var speed := 360
var target: Vector2


func _ready() -> void:
	speed *= GameManager.get_missile_speed_multiplier()
	look_at(target)
	connect("area_entered", Callable(self, "_on_area_entered"))
	add_to_group("projectile")


func _process(delta: float) -> void:
	var direction := target - global_position
	var zone_multiplier := IonFieldUtils.get_speed_multiplier_at(global_position, true)
	var step := speed * zone_multiplier * delta

	if direction.length() < step:
		explode()
	else:
		position += direction.normalized() * step


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("enemy"):
		explode()


func explode() -> void:
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		get_tree().current_scene.add_child(explosion)
	queue_free()
