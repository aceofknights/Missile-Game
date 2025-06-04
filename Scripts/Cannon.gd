extends Area2D

@export var projectile_scene: PackedScene
@export var fire_rate = 0.5
@export var max_ammo = 10
@export var reload_time = 2.0

var cooldown = 0.0
var current_ammo = 10
var reloading = false

func _process(delta):
	# Rotate cannon to face mouse
	look_at(get_global_mouse_position())

	# Handle cooldown
	if cooldown > 0:
		cooldown -= delta

	if current_ammo < max_ammo and not reloading:
		start_reload()

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if cooldown <= 0:
			fire()
			cooldown = fire_rate

func fire():
	if current_ammo > 0:
		current_ammo -= 1
		var projectile = projectile_scene.instantiate()
		projectile.global_position = global_position
		projectile.target = get_global_mouse_position()
		get_tree().current_scene.add_child(projectile)

func start_reload():
	reloading = true
	print("🔄 Reloading...")
	await get_tree().create_timer(reload_time).timeout
	current_ammo += 1
	reloading = false
	print("✅ Reloaded")
