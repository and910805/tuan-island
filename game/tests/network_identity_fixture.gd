extends SceneTree

const World = preload("res://scripts/world.gd")

func _initialize() -> void:
	var world := World.new()
	if not world.load_world(OS.get_cmdline_user_args()[0]):
		quit(1)
		return
	world.add_player("legacy-character-original", "Original")
	world.state.players["legacy-character-original"].coins = 271
	quit(0 if world.save() else 1)
