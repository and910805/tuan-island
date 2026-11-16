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
		var center_x:=42 if role=="alpha" else 46
		player.x=42.5 if role=="alpha" else 44.5
		player.y=36.5
		player.inventory.charcoal=3
		player.inventory.harvester=1
		for y in range(35,38):
			for x in range(center_x-1,center_x+2):
				var key:=World.key(Vector2i(x,y))
				world.state.crops[key]={"owner":token,"kind":"radish","growth":90.0,"wet":false,"remaining":1}
				world.state.removed[key]=true
	world.save_path=args[0]
	quit(0 if world.save() else 1)
