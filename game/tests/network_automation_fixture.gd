extends SceneTree
const World = preload("res://scripts/world.gd")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=1:
		quit(1)
		return
	var world := World.new()
	for role in ["alpha","beta"]:
		var token := "network-%s-test"%role
		world.add_player(token,role)
		var player: Dictionary = world.state.players[token]
		player.x=53.5
		player.y=24.5
		player.inventory.reinforced_pick=1
		player.crafted_reinforced_pick=true
	world.state.objects["53,25"]={"type":"sprinkler","owner":"network-alpha-test","items":{},"water":0,"enabled":false,"next_water":0,"last_water":-1}
	world.state.crops["53,26"]={"owner":"network-alpha-test","kind":"radish","wet":false,"growth":0,"remaining":1}
	world.save_path=args[0]
	quit(0 if world.save() else 1)
