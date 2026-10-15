extends GutTest

## Godot 4.8 rejects re-binding inherited names, so `stream =` and set_stream() on a
## ResonancePlayer reach AudioStreamPlayer3D directly and bypass the Resonance wrapper
## bookkeeping. get_inner_stream() and clearing player_config must use the newly assigned
## stream, not the one cached when the wrapper was built.


func _tone() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 44100
	var data := PackedByteArray()
	data.resize(882)
	wav.data = data
	return wav


func _spawn_wrapped(first: AudioStream) -> ResonancePlayer:
	var player := ClassDB.instantiate("ResonancePlayer") as ResonancePlayer
	player.player_config = ResonancePlayerConfig.new()
	player.stream = first
	add_child_autofree(player)
	return player


func test_inner_stream_follows_inherited_stream_assignment() -> void:
	var first := _tone()
	var second := _tone()
	var player := _spawn_wrapped(first)
	await wait_process_frames(1)
	assert_eq(player.stream.get_class(), "ResonanceStream", "stream is wrapped once the player is ready")
	assert_eq(player.get_inner_stream(), first)

	player.stream = second
	assert_eq(player.get_inner_stream(), second)


func test_clearing_config_restores_inherited_stream_assignment() -> void:
	var first := _tone()
	var second := _tone()
	var player := _spawn_wrapped(first)
	await wait_process_frames(1)

	player.stream = second
	player.player_config = null
	assert_eq(player.stream, second)
