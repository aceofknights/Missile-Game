extends Area2D

signal weak_point_destroyed

@export var max_hp: int = 3

@export var flash_speed: float = 10.0
@export var flash_colors: Array[Color] = [
	Color(1.0, 0.1, 0.1, 1.0), # red
	Color(0.2, 0.5, 1.0, 1.0), # blue
	Color(1.0, 0.9, 0.2, 1.0)  # yellow
]

@onready var hp_label: Label = $HPLabel
@onready var sprite: Sprite2D = $Sprite2D

var current_hp: int = 0
var destroyed: bool = false
var _life_time: float = 0.0


func _ready() -> void:
	current_hp = max(1, max_hp)
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)
	_update_label()
	_update_flash_color()


func _process(delta: float) -> void:
	_life_time += delta
	_update_flash_color()


func _on_area_entered(area: Area2D) -> void:
	if destroyed:
		return

	if area.name == "Projectile":
		area.queue_free()
		_apply_damage()
	elif area.name == "Explosion":
		_apply_damage()


func _apply_damage() -> void:
	if destroyed:
		return

	current_hp -= 1
	_update_label()

	if current_hp <= 0:
		destroyed = true
		emit_signal("weak_point_destroyed")
		queue_free()


func _update_label() -> void:
	if hp_label:
		hp_label.text = "Laser %d" % current_hp


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
