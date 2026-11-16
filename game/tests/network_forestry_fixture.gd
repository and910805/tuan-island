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
		player.x=41.5
		player.y=35.5
		player.inventory.charcoal=4
	var owner:="network-alpha-test"
	world.state.objects["41,34"]={"type":"forester","owner":owner,"items":{"wood":6,"fiber":2,"resin":1}}
	world.state.objects["41,34"].merge(World.FORESTRY.fresh(0))
	world.state.forest["41,32"]={"owner":owner,"growth":World.TREE_TIME,"mature":true}
	world.save_path=args[0]
	quit(0 if world.save() else 1)
