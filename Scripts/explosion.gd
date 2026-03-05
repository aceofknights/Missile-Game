extends Area2D
class_name Explosion

@export var gives_reward := true

# Peak collision radius you chose
@export var max_radius: float = 26.0

# Visual mapping: when radius == max_radius, the explosion's parent scale == max_visual_scale
# (keep this at your old peak size, probably 2.0)
@export var max_visual_scale: float = 2.0

# Timing
@export var grow_time: float = 0.5
@export var hold_time: float = 0.2
@export var shrink_time: float = 0.15

# Optional: keep sprite hidden until it has some size
@export var min_visible_t: float = 0.02

@onready var col: CollisionShape2D = $CollisionShape2D
@onready var vis: CanvasItem = $Sprite2D  # Sprite2D or AnimatedSprite2D works

var _t: float = 0.0     # 0..1 single source of truth
var _hit := {}

func _ready():
	monitoring = true
	monitorable = true

	# prevent shared-shape weirdness
	col.shape = col.shape.duplicate(true)

	# start perfectly at zero
	_t = 0.0
	_apply_t()

	connect("area_entered", Callable(self, "_on_area_entered"))

	var tween := get_tree().create_tween()

	# Grow
	if grow_time <= 0.0:
		_t = 1.0
		_apply_t()
	else:
		tween.tween_property(self, "_t", 1.0, grow_time)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_callback(Callable(self, "_apply_t"))

	# Hold
	if hold_time > 0.0:
		tween.tween_interval(hold_time)

	# Shrink
	if shrink_time <= 0.0:
		_t = 0.0
		_apply_t()
	else:
		tween.tween_property(self, "_t", 0.0, shrink_time)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_callback(Callable(self, "_apply_t"))

	tween.tween_callback(Callable(self, "queue_free"))

func _process(_delta):
	# Keep them synced even between tween callbacks
	_apply_t()

func _apply_t():
	_t = clamp(_t, 0.0, 1.0)

	# 1) Visual size (parent scale)
	var s := max_visual_scale * _t
	scale = Vector2(s, s)

	# 2) Collision radius
	(col.shape as CircleShape2D).radius = max_radius * _t

	# 3) Visibility (prevents “sprite appears bigger on spawn”)
	vis.visible = (_t >= min_visible_t)

func _on_area_entered(area: Area2D):
	if not area.is_in_group("enemy"): return

	var id := area.get_instance_id()
	if _hit.has(id): return
	_hit[id] = true

	if area.has_method("die"):
		area.die(not gives_reward)
