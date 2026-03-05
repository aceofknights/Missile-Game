extends Area2D

@export var projectile_scene: PackedScene
@export var cannon_id := GameManager.CANNON_MIDDLE
@export var fire_rate := 0.5

var cooldown := 0.0
var shots_in_cycle := 0


func _ready() -> void:
	add_to_group("cannon")
	add_to_group("defense_target")
	monitoring = true
	monitorable = true
	connect("area_entered", Callable(self, "_on_area_entered"))
	_refresh_visibility_state()


func _process(delta: float) -> void:
	if not _can_operate():
		return

	look_at(get_global_mouse_position())

	if cooldown > 0.0:
		cooldown -= delta


func _input(event):
	if not _can_operate():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if cooldown <= 0.0 and fire():
			shots_in_cycle += 1
			if shots_in_cycle >= GameManager.get_cannon_shots_per_cycle(cannon_id):
				shots_in_cycle = 0
				cooldown = GameManager.get_cannon_fire_rate(cannon_id, fire_rate)


func _can_operate() -> bool:
	_refresh_visibility_state()
	return GameManager.is_cannon_unlocked(cannon_id) and not GameManager.is_cannon_destroyed(cannon_id)


func _refresh_visibility_state() -> void:
	var active = GameManager.is_cannon_unlocked(cannon_id) and not GameManager.is_cannon_destroyed(cannon_id)
	visible = active
	monitorable = active
	monitoring = active
	var cs = get_node_or_null("CollisionShape2D")
	if cs:
		cs.disabled = not active


func fire() -> bool:
	if not GameManager.spend_cannon_ammo(cannon_id, 1):
		return false

	var projectile = projectile_scene.instantiate()
	projectile.global_position = global_position
	projectile.target = get_global_mouse_position()
	get_tree().current_scene.add_child(projectile)
	return true


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("enemy"):
		GameManager.destroy_cannon(cannon_id)
		_refresh_visibility_state()


func die() -> void:
	GameManager.destroy_cannon(cannon_id)
	_refresh_visibility_state()
