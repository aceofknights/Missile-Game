extends Node2D

signal strike_impact(target: Node2D, target_name: String)

@export var speed: float = 1800.0
@export var impact_distance: float = 20.0

@export var flash_speed: float = 10.0
@export var flash_colors: Array[Color] = [
	Color(1.0, 0.1, 0.1, 1.0), # red
	Color(0.2, 0.5, 1.0, 1.0), # blue
	Color(1.0, 0.9, 0.2, 1.0)  # yellow
]

@onready var sprite: Sprite2D = $Sprite2D

var _target_node: Node2D = null
var _target_name: String = ""
var _fallback_target_position: Vector2 = Vector2.ZERO
var _life_time: float = 0.0


func setup_strike(spawn_position: Vector2, target_node: Node2D, target_name: String) -> void:
	global_position = spawn_position
	_target_node = target_node
	_target_name = target_name
	if is_instance_valid(_target_node):
		_fallback_target_position = _target_node.global_position
	else:
		_fallback_target_position = spawn_position


func _ready() -> void:
	_update_flash_color()


func _process(delta: float) -> void:
	_life_time += delta
	_update_flash_color()

	var target_position: Vector2 = _resolve_target_position()
	var offset: Vector2 = target_position - global_position
	var distance: float = offset.length()
	if distance <= impact_distance:
		_impact()
		return

	var step: float = speed * delta
	if distance <= step:
		global_position = target_position
		_impact()
		return

	var direction: Vector2 = offset / distance
	rotation = direction.angle()
	global_position += direction * step


func _resolve_target_position() -> Vector2:
	if is_instance_valid(_target_node):
		_fallback_target_position = _target_node.global_position
	return _fallback_target_position


func _impact() -> void:
	emit_signal("strike_impact", _target_node, _target_name)
	queue_free()


func _update_flash_color() -> void:
	if sprite == null:
		return
	if flash_colors.is_empty():
		return

	sprite.modulate = _get_blended_flash_color()


func _get_blended_flash_color() -> Color:
	if flash_colors.size() == 1:
		return flash_colors[0]

	var cycle_pos: float = _life_time * flash_speed
	var whole_step: float = floor(cycle_pos)
	var base_index: int = int(whole_step) % flash_colors.size()
	var next_index: int = (base_index + 1) % flash_colors.size()
	var blend_t: float = cycle_pos - whole_step

	return flash_colors[base_index].lerp(flash_colors[next_index], blend_t)
