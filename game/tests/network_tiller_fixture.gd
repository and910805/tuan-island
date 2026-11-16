extends SceneTree
const World=preload("res://scripts/world.gd")
func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1:
		quit(1)
		return
	var world:=World.new()
	for role in ["alpha","beta"]:
		var token:="network-%s-test"%role
		world.add_player(token,role)
		var player:Dictionary=world.state.players[token]
		player.x=42.5
		player.y=36.5
		player.inventory.charcoal=3
		player.inventory.tiller=1
	world.save_path=args[0]
	quit(0 if world.save() else 1)
