extends Area2D

signal weak_point_destroyed

@export var max_hp: int = 3

@onready var hp_label: Label = $HPLabel

var current_hp: int = 0
var destroyed: bool = false


func _ready() -> void:
	current_hp = max(1, max_hp)
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)
	_update_label()


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
