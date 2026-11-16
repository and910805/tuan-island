extends SceneTree

const World = preload("res://scripts/world.gd")

func _initialize() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="):
			path = arg.trim_prefix("--save=")
	if path.is_empty():
		quit(1)
		return
	var world = World.new()
	world.add_player("network-alpha-test", "alpha")
	world.add_player("network-beta-test", "beta")
	world.state.players["network-alpha-test"].collection.crops = {"radish": true, "lettuce": true, "wheat": true}
	world.state.players["network-beta-test"].collection.crops = {"carrot": true, "potato": true, "tomato": true}
	world.save_path = path
	quit(0 if world.save() else 1)
