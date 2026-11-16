extends SceneTree

const World = preload("res://scripts/world.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Pass the stage-one source and a new absolute path for its copy")
		quit(1)
		return
	var source := args[0]
	var copy := args[1]
	if not FileAccess.file_exists(source) or FileAccess.file_exists(copy) or FileAccess.file_exists(copy + ".bak"):
		push_error("The source must exist and the copy path must be unused")
		quit(1)
		return
	var original := FileAccess.get_file_as_string(source)
	var original_state: Variant = JSON.parse_string(original)
	var world := World.new()
	if not original_state is Dictionary or DirAccess.copy_absolute(source, copy) != OK or not world.load_world(copy):
		push_error("Could not load the stage-one copy")
		quit(1)
		return
	var counts := {"long_bench": 0, "planter": 0}
	for key in world.state.objects:
		var kind: String = world.state.objects[key].type
		if not counts.has(kind):
			continue
		var parts: PackedStringArray = key.split(",")
		if not world.blocked(Vector2i(int(parts[0]), int(parts[1]))):
			push_error("Existing furniture lost collision: " + key)
			quit(1)
			return
		counts[kind] += 1
	if counts.long_bench < 1 or counts.planter < 1 or not world.save():
		push_error("Fixture furniture is missing or writing the copy failed")
		quit(1)
		return
	var reloaded := World.new()
	if not reloaded.load_world(copy) or FileAccess.get_file_as_string(source) != original:
		push_error("Could not reload the copy or the original file changed")
		quit(1)
		return
	print("STAGE1_SAVE players=%d crops=%d long_bench=%d planter=%d failures=0" % [
		reloaded.state.players.size(), reloaded.state.crops.size(), counts.long_bench, counts.planter])
	quit(0)
