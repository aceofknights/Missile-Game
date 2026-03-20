extends Area2D
class_name Explosion

@export var gives_reward: bool = true

@export var max_radius: float = 26.0
@export var max_visual_scale: float = 2.0

@export var grow_time: float = 0.5
@export var hold_time: float = 0.2
@export var shrink_time: float = 0.15

@export var min_visible_t: float = 0.02

@export var flash_speed: float = 10
@export var flash_colors: Array[Color] = [
	Color(1.0, 0.1, 0.1, 1.0), # red
	Color(0.2, 0.5, 1.0, 1.0), # blue
	Color(1.0, 0.9, 0.2, 1.0)  # yellow
]

@export var fade_out: bool = true

@onready var col: CollisionShape2D = $CollisionShape2D
@onready var vis: Sprite2D = $Sprite2D

var _t: float = 0.0
var _life_time: float = 0.0
var _hit: Dictionary = {}

func _ready() -> void:
	max_radius += GameManager.get_explosion_radius_bonus()
	hold_time += GameManager.get_explosion_duration_bonus()
	monitoring = true
	monitorable = true

	col.shape = col.shape.duplicate(true)

	_t = 0.0
	_life_time = 0.0
	_apply_t()

	connect("area_entered", Callable(self, "_on_area_entered"))

	var tween: Tween = get_tree().create_tween()

	if grow_time <= 0.0:
		_t = 1.0
		_apply_t()
	else:
		tween.tween_property(self, "_t", 1.0, grow_time)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	if hold_time > 0.0:
		tween.tween_interval(hold_time)

	if shrink_time <= 0.0:
		_t = 0.0
		_apply_t()
	else:
		tween.tween_property(self, "_t", 0.0, shrink_time)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	tween.tween_callback(Callable(self, "queue_free"))

func _process(delta: float) -> void:
	_life_time += delta
	_apply_t()

func _apply_t() -> void:
	_t = clamp(_t, 0.0, 1.0)

	var s: float = max_visual_scale * _t
	scale = Vector2(s, s)

	var circle_shape := col.shape as CircleShape2D
	if circle_shape:
		circle_shape.radius = max_radius * _t

	vis.visible = (_t >= min_visible_t)

	if vis.visible and flash_colors.size() > 0:
		var c: Color = _get_blended_flash_color()

		if fade_out:
			c.a *= _t

		vis.modulate = c

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
	if not area.is_in_group("enemy"):
		return

	var id: int = area.get_instance_id()
	if _hit.has(id):
		return
	_hit[id] = true

	if area.has_method("die"):
		area.die(not gives_reward)
