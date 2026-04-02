extends Node

@export var playlist: Array[AudioStream] = []
@export var gap_between_songs: float = 5.0
@export var fade_out_duration: float = 1.5
@export var fade_in_duration: float = 1.0
@export var use_fade_in: bool = true
@export var use_fade_out: bool = true
@export var avoid_repeating_last_song: bool = true
@export var target_volume_db: float = 0.0
@export var start_on_ready: bool = true

@onready var music_player: AudioStreamPlayer = $MusicPlayer

var _last_index: int = -1
var _rng := RandomNumberGenerator.new()
var _is_transitioning: bool = false


func _ready() -> void:
	_rng.randomize()
	if start_on_ready:
		_play_next_song()


func _play_next_song() -> void:
	if playlist.is_empty():
		push_warning("MusicManager: playlist is empty.")
		return

	var next_index := _get_random_song_index()
	_last_index = next_index
	music_player.stream = playlist[next_index]

	if use_fade_in:
		music_player.volume_db = -40.0
	else:
		music_player.volume_db = target_volume_db

	music_player.play()

	if use_fade_in:
		await _fade_volume(-40.0, target_volume_db, fade_in_duration)

	await music_player.finished
	await _handle_song_end()


func _handle_song_end() -> void:
	if _is_transitioning:
		return

	_is_transitioning = true

	if use_fade_out and music_player.playing:
		await _fade_volume(music_player.volume_db, -40.0, fade_out_duration)
		music_player.stop()

	await get_tree().create_timer(gap_between_songs).timeout
	_is_transitioning = false
	_play_next_song()


func _get_random_song_index() -> int:
	if playlist.size() == 1:
		return 0

	var index := _rng.randi_range(0, playlist.size() - 1)

	if avoid_repeating_last_song:
		while index == _last_index:
			index = _rng.randi_range(0, playlist.size() - 1)

	return index


func _fade_volume(from_db: float, to_db: float, duration: float) -> void:
	if duration <= 0.0:
		music_player.volume_db = to_db
		return

	var tween := create_tween()
	tween.tween_property(music_player, "volume_db", to_db, duration).from(from_db)
	await tween.finished
