extends Node


func _on_boss_defeated():
	GameManager.boss_defeated()

func _on_player_died():
	GameManager.player_died()
