extends GutTest

## A ResonancePlayer freed within a few frames of play() (a level swap, a pooled
## one-shot) leaves its voice in the AudioServer, which frees it later. The voice
## used to unregister from the dead player and abort with
## "mutex lock failed: Invalid argument". A crash fails the whole run.

const ROUNDS: int = 60
const PLAYERS_PER_ROUND: int = 6

var _runtime: Node
var _config: ResonancePlayerConfig
var _stream: AudioStreamWAV


func before_all() -> void:
	_config = ResonancePlayerConfig.new()
	_config.reflections_enabled = 0
	_config.pathing_enabled_override = 0
	_stream = _make_tone_stream()
	_runtime = ClassDB.instantiate("ResonanceRuntime")
	add_child(_runtime)
	await wait_process_frames(2)


func after_all() -> void:
	if is_instance_valid(_runtime):
		_runtime.queue_free()
	await wait_process_frames(2)


func _make_tone_stream() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 44100
	wav.stereo = false
	var frames: int = 4410
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		data.encode_s16(i * 2, int(sin(float(i) * 0.05) * 12000.0))
	wav.data = data
	return wav


func _spawn_playing() -> ResonancePlayer:
	var player := ClassDB.instantiate("ResonancePlayer") as ResonancePlayer
	player.player_config = _config
	player.stream = _stream
	add_child(player)
	player.play()
	return player


func test_free_right_after_play_does_not_abort() -> void:
	for round_index in ROUNDS:
		var players: Array[ResonancePlayer] = []
		for i in PLAYERS_PER_ROUND:
			players.append(_spawn_playing())
		await wait_process_frames(1)
		for player in players:
			if round_index % 2 == 0:
				player.free()
			else:
				player.stop()
				player.queue_free()
	await wait_process_frames(10)
	pass_test("players freed after play() released their voices without aborting")
