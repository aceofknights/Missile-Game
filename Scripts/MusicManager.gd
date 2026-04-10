extends AudioStreamPlayer

var current_id: String = ""

func play_music(stream: AudioStream, music_id: String = "") -> void:
	if playing and current_id == music_id:
		return

	self.stream = stream
	current_id = music_id
	play()

func stop_music() -> void:
	if playing:
		stop()
	current_id = ""
