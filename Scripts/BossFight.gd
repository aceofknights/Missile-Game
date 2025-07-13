extends Node

signal boss_defeated

@export var health: int = 5
var speed = 100

func take_damage(amount: int):
	health -= amount
	if health <= 0:
		die()

func die():
	GameManager.boss_defeated()
	emit_signal("boss_defeated")
	queue_free()
	
func _on_player_died():
	GameManager.player_died()

func _process(delta):
	move_pattern(delta)
	
func move_pattern(delta):
	return
