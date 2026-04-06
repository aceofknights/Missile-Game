extends Area2D

signal enemy_died
signal boss_defeated
signal start_death_animation(boss: Node)
@export var explosion_scene: PackedScene
@export var missile_scene: PackedScene
@export var scatter_missile_scene: PackedScene
@export var move_speed: float = 120.0
@export var max_health: int = 3
@export var shield_up_duration: float = 3.5
@export var shield_down_duration: float = 2.0
@export var missile_drop_interval: float = 1.0

# Scatter starts at 8 seconds and speeds up each time boss is hit
@export var scatter_start_interval: float = 8.0
@export var scatter_interval_step: float = 2.0
@export var scatter_min_interval: float = 3.0

@export var boss_name: String = "UFO BOSS"

# Drag your actual visible sprite here in the inspector
@export_node_path("CanvasItem") var flash_sprite_path: NodePath

# Hit flash settings
@export var hit_flash_white: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var hit_flash_red: Color = Color(1.0, 0.25, 0.25, 1.0)
@export var hit_flash_step_time: float = 0.08
@export var hit_flash_cycles: int = 3

@onready var shield_timer: Timer = $ShieldTimer
@onready var missile_timer: Timer = $MissileTimer
@onready var scatter_timer: Timer = $ScatterTimer
@onready var boss_health: Label = get_node_or_null("boss_health") as Label
@onready var shield_sprite: Sprite2D = $ShieldSprite
@onready var flash_sprite: CanvasItem = get_node_or_null(flash_sprite_path) as CanvasItem

var health: int = 3
var shield_active: bool = true
var hit_used_this_down_window: bool = false
var move_direction: float = 1.0
var is_dead: bool = false
var current_scatter_interval: float = 8.0

var _base_sprite_modulate: Color = Color(1, 1, 1, 1)
var _hit_flash_tween: Tween


func _add_to_scene(node: Node) -> void:
	var parent := get_parent()
	if is_instance_valid(parent):
		parent.add_child(node)
	else:
		get_tree().root.add_child(node)


func _ready() -> void:
	health = max_health
	current_scatter_interval = scatter_start_interval
	add_to_group("enemy")
	add_to_group("boss")

	if flash_sprite:
		_base_sprite_modulate = flash_sprite.modulate
		print("✅ Boss flash sprite found:", flash_sprite.name)
	else:
		print("❌ Boss flash sprite NOT found. Set flash_sprite_path in the inspector.")

	shield_timer.wait_time = shield_up_duration
	shield_timer.timeout.connect(_on_shield_timer_timeout)
	shield_timer.start()

	missile_timer.wait_time = missile_drop_interval
	missile_timer.timeout.connect(_on_missile_timer_timeout)
	missile_timer.start()

	scatter_timer.one_shot = true
	scatter_timer.timeout.connect(_on_scatter_timer_timeout)
	_schedule_next_scatter()

	_set_shield_active(true)
	print("👾 Boss ready:", boss_name, " HP=", health)


func _process(delta: float) -> void:
	if is_dead:
		return

	if boss_health:
		boss_health.text = "Health %d" % health

	var viewport := get_viewport_rect().size
	var boss_speed: float = 1.0

	if health >= 3:
		boss_speed = 1.0
	elif health == 2:
		boss_speed = 2.0
	else:
		boss_speed = 5.0

	global_position.x += move_direction * boss_speed * move_speed * delta

	if global_position.x < 120:
		global_position.x = 120
		move_direction = 1.0
	elif global_position.x > viewport.x - 120:
		global_position.x = viewport.x - 120
		move_direction = -1.0


func die(no_reward: bool = false) -> void:
	if is_dead:
		return
	if shield_active:
		print("🛡️ Boss shield blocked the hit")
		return
	if hit_used_this_down_window:
		print("🛡️ Boss already took a hit during this shield break")
		return

	hit_used_this_down_window = true
	health -= 1
	_play_hit_flash()

	# Bring shield back immediately after a successful hit
	_set_shield_active(true)
	shield_timer.stop()
	shield_timer.wait_time = shield_up_duration
	shield_timer.start()

	print("👾 Boss hit! Remaining HP: %d" % health)
	print("🛡️ Shield restored after hit")

	if health <= 0:
		_die_for_real(no_reward)
		return

	current_scatter_interval = max(scatter_min_interval, current_scatter_interval - scatter_interval_step)
	print("☄️ Scatter interval now: %.2f seconds" % current_scatter_interval)

	_schedule_next_scatter()


func _die_for_real(no_reward: bool = false) -> void:
	if is_dead:
		return

	_prepare_for_death_animation()

	if not no_reward:
		GameManager.add_resources(10)

	emit_signal("start_death_animation", self)


func _on_shield_timer_timeout() -> void:
	if shield_active:
		_set_shield_active(false)
		hit_used_this_down_window = false
		shield_timer.wait_time = shield_down_duration
		print("⚡ Boss shield DOWN")
	else:
		_set_shield_active(true)
		shield_timer.wait_time = shield_up_duration
		print("🛡️ Boss shield UP")

	shield_timer.start()


func _on_missile_timer_timeout() -> void:
	if is_dead:
		return
	spawn_normal_missile()


func _on_scatter_timer_timeout() -> void:
	if is_dead:
		return
	spawn_scatter_missile()
	_schedule_next_scatter()


func _schedule_next_scatter() -> void:
	if is_dead:
		return
	scatter_timer.stop()
	scatter_timer.wait_time = current_scatter_interval
	scatter_timer.start()


func spawn_normal_missile() -> void:
	if is_dead:
		return
	if missile_scene == null:
		return

	var missile = missile_scene.instantiate()
	GameManager.enemies_alive += 1
	missile.connect("enemy_died", Callable(GameManager, "_on_enemy_died"))

	var viewport := get_viewport_rect().size
	var target := Vector2(randf_range(40.0, viewport.x - 40.0), viewport.y)
	var direction := (target - global_position).normalized()

	missile.global_position = global_position + Vector2(0, 30)
	missile.velocity = direction

	_add_to_scene(missile)


func spawn_scatter_missile() -> void:
	if is_dead:
		return
	if scatter_missile_scene == null:
		return

	var missile = scatter_missile_scene.instantiate()
	GameManager.enemies_alive += 1
	missile.connect("enemy_died", Callable(GameManager, "_on_enemy_died"))

	var viewport := get_viewport_rect().size
	var target := Vector2(randf_range(80.0, viewport.x - 80.0), viewport.y)
	var direction := (target - global_position).normalized()

	missile.global_position = global_position + Vector2(0, 35)
	missile.velocity = direction

	_add_to_scene(missile)
	print("☄️ Scatter missile launched")

func get_boss_visual_node() -> CanvasItem:
	return flash_sprite


func get_boss_death_particles() -> GPUParticles2D:
	return get_node_or_null("DeathParticles") as GPUParticles2D

func _prepare_for_death_animation() -> void:
	is_dead = true
	missile_timer.stop()
	shield_timer.stop()
	scatter_timer.stop()
	_set_shield_active(false)

	if _hit_flash_tween:
		_hit_flash_tween.kill()
		_hit_flash_tween = null

	if flash_sprite:
		flash_sprite.modulate = _base_sprite_modulate

	monitoring = false
	monitorable = false

	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape:
		collision_shape.disabled = true

func get_boss_body_size() -> Vector2:
	var sprite_node := flash_sprite as Sprite2D
	if sprite_node and sprite_node.texture:
		return sprite_node.texture.get_size() * sprite_node.scale

	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape and collision_shape.shape is RectangleShape2D:
		var rect_shape := collision_shape.shape as RectangleShape2D
		return rect_shape.size * collision_shape.scale

	if collision_shape and collision_shape.shape is CircleShape2D:
		var circle_shape := collision_shape.shape as CircleShape2D
		var diameter: float = circle_shape.radius * 2.0
		return Vector2(diameter, diameter) * collision_shape.scale

	return Vector2(180.0, 120.0)

func _set_shield_active(value: bool) -> void:
	shield_active = value
	if shield_sprite:
		shield_sprite.visible = shield_active


func _play_hit_flash() -> void:
	if flash_sprite == null:
		print("❌ Cannot flash boss: flash_sprite is null")
		return

	if _hit_flash_tween:
		_hit_flash_tween.kill()

	print("✨ Boss hit flash playing")
	flash_sprite.modulate = _base_sprite_modulate
	_hit_flash_tween = create_tween()

	var cycles: int = max(1, hit_flash_cycles)
	for _i in range(cycles):
		_hit_flash_tween.tween_property(flash_sprite, "modulate", hit_flash_white, hit_flash_step_time)
		_hit_flash_tween.tween_property(flash_sprite, "modulate", hit_flash_red, hit_flash_step_time)

	_hit_flash_tween.tween_property(flash_sprite, "modulate", _base_sprite_modulate, hit_flash_step_time)
	_hit_flash_tween.finished.connect(_on_hit_flash_finished)

func _on_hit_flash_finished() -> void:
	_hit_flash_tween = null
	if flash_sprite:
		flash_sprite.modulate = _base_sprite_modulate


func get_boss_health() -> int:
	return health


func get_boss_max_health() -> int:
	return max_health


func is_boss_dead() -> bool:
	return is_dead


func get_boss_display_name() -> String:
	return boss_name
