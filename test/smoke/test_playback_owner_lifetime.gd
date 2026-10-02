extends SceneTree

## Engine-backed teardown regression: stream assignment can instantiate a
## playback before play(), so freeing a never-started player must orphan it too.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ClassDB.class_exists("ResonancePlayer"):
		push_error("Nexus Resonance GDExtension did not load")
		quit(1)
		return
	var config_script = load("res://addons/nexus_resonance/scripts/resonance_player_config.gd")
	if config_script == null:
		push_error("Missing ResonancePlayerConfig")
		quit(1)
		return
	for iteration in 32:
		var player = ClassDB.instantiate("ResonancePlayer")
		var config = config_script.new()
		config.reflections_enabled = 0
		config.pathing_enabled_override = 0
		player.player_config = config
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 44100
		var data := PackedByteArray()
		data.resize(88200)
		stream.data = data
		player.stream = stream
		root.add_child(player)
		if iteration % 3 == 1:
			# Replacing the engine stream releases a playback before its owner.
			player.stream = null
		elif iteration % 3 == 2:
			player.max_polyphony = 3
			player.play()
			player.play()
			await process_frame
		player.free()
		await process_frame
	for frame in 4:
		await process_frame
	print("PASS: playback owner lifetime (never-started, replaced, overlapping)")
	quit(0)
