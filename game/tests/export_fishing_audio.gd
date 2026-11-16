extends SceneTree
const Audio = preload("res://scripts/soft_audio.gd")
func _initialize() -> void:
	var directory := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-dir="):directory=arg.trim_prefix("--qa-dir=")
	if directory.is_empty() or DirAccess.make_dir_recursive_absolute(directory) != OK:
		quit(1)
		return
	for cue in ["fish_cast", "fish_bite", "fish_catch"]:
		var sound: AudioStreamWAV = Audio.make_cue(cue)
		if sound == null or sound.save_to_wav(directory.path_join(cue + ".wav")) != OK:
			push_error("Cannot export " + cue)
			quit(1)
			return
		print("FISHING_CUE_EXPORTED ",cue," bytes=",sound.data.size()," sample_rate=",sound.mix_rate)
	quit(0)
