extends Area2D
class_name Explosion

@export var gives_reward: bool = true

@export var max_visual_scale: float = 2.0
@export var size_multiplier: float = 0.2

@export var grow_time: float = 0.5
@export var hold_time: float = 0.2
@export var shrink_time: float = 0.15

@export var min_visible_t: float = 0.02

@export var flash_speed: float = 10.0
@export var flash_colors: Array[Color] = [
	Color(1.0, 0.1, 0.1, 1.0), # red
	Color(0.2, 0.5, 1.0, 1.0), # blue
	Color(1.0, 0.9, 0.2, 1.0)  # yellow
]

@export var fade_out: bool = true
@export var explosion_sound: AudioStream

@onready var col: CollisionShape2D = $CollisionShape2D
@onready var vis: Sprite2D = $Sprite2D

var _t: float = 0.0
var _life_time: float = 0.0
var _hit: Dictionary = {}
var _base_sprite_radius: float = 1.0


func _ready() -> void:
	monitoring = true
	monitorable = true
	add_to_group("player_explosion")

	if col.shape:
		col.shape = col.shape.duplicate(true)

	area_entered.connect(_on_area_entered)

	_cache_base_sprite_radius()

	_t = 0.0
	_life_time = 0.0
	_apply_t()

	_play_sound(explosion_sound)

	var tween: Tween = get_tree().create_tween()

	if grow_time <= 0.0:
		_t = 1.0
	else:
		tween.tween_property(self, "_t", 1.0, grow_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	if hold_time > 0.0:
		tween.tween_interval(hold_time + GameManager.get_explosion_duration_bonus())

	if shrink_time <= 0.0:
		_t = 0.0
	else:
		tween.tween_property(self, "_t", 0.0, shrink_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	tween.tween_callback(queue_free)


func _process(delta: float) -> void:
	_life_time += delta


func _physics_process(_delta: float) -> void:
	_apply_t()


func _cache_base_sprite_radius() -> void:
	if vis == null or vis.texture == null:
		_base_sprite_radius = 1.0
		return

	var tex_size: Vector2 = vis.texture.get_size()
	_base_sprite_radius = max(tex_size.x, tex_size.y) * 0.5

	if _base_sprite_radius <= 0.0:
		_base_sprite_radius = 1.0


func _play_sound(sound: AudioStream) -> void:
	if sound == null:
		return

	var player := AudioStreamPlayer.new()
	add_child(player)
	player.stream = sound
	player.bus = "SFX"
	player.play()
	player.finished.connect(player.queue_free)


func _apply_t() -> void:
	_t = clamp(_t, 0.0, 1.0)

	if vis:
		var final_scale: float = max_visual_scale * size_multiplier * _t
		vis.scale = Vector2(final_scale, final_scale)
		vis.visible = (_t >= min_visible_t)

		if vis.visible and flash_colors.size() > 0:
			var c: Color = _get_blended_flash_color()
			if fade_out:
				c.a *= _t
			vis.modulate = c

	var circle_shape := col.shape as CircleShape2D
	if circle_shape and vis:
		var radius_from_sprite: float = _base_sprite_radius * vis.scale.x
		radius_from_sprite += GameManager.get_explosion_radius_bonus() * _t
		circle_shape.radius = radius_from_sprite


func _get_blended_flash_color() -> Color:
	if flash_colors.size() == 1:
		return flash_colors[0]

	var cycle_pos: float = _life_time * flash_speed
	var whole_step: float = floor(cycle_pos)
	var base_index: int = int(whole_step) % flash_colors.size()
	var next_index: int = (base_index + 1) % flash_colors.size()
	var blend_t: float = cycle_pos - whole_step

	return flash_colors[base_index].lerp(flash_colors[next_index], blend_t)


func _on_area_entered(area: Area2D) -> void:
	var id: int = area.get_instance_id()
	if _hit.has(id):
		return
	_hit[id] = true

	if area.is_in_group("enemy"):
		if area.has_method("die"):
			area.die(not gives_reward)
		return

	if area.is_in_group("weak_point"):
		if area.has_method("apply_explosion_damage"):
			area.apply_explosion_damage()
