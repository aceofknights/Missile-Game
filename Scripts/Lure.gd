extends Area2D

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	add_to_group("player_lure")

	if anim and anim.sprite_frames:
		anim.play("default")

func _process(_delta: float) -> void:
	var now_seconds := Time.get_ticks_msec() / 1000.0

	if not GameManager.is_lure_active(now_seconds):
		queue_free()
