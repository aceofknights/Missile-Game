extends "res://scripts/BossFight.gd"

@export var enemy_scene: PackedScene

@onready var teleport_timer = $TeleportTimer
@onready var missile_timer = $MissileTimer
@onready var enemy_rain_timer = $EnemyRainTimer

# Called when the node enters the scene tree for the first time.
func _ready():
	return

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
