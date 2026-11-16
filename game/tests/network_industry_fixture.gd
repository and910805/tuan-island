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
		player.x=52.5
		player.y=24.5
		player.inventory.reinforced_pick=1
		player.crafted_reinforced_pick=true
	var owner:="network-alpha-test"
	world.state.objects["53,24"]={"type":"water_pump","owner":owner,"items":{},"enabled":false}
	world.state.objects["53,25"]={"type":"water_pipe","owner":owner,"items":{}}
	world.state.objects["53,26"]={"type":"water_tank","owner":owner,"items":{},"water":0}
	world.state.objects["52,25"]={"type":"sawmill","owner":owner,"items":{},
		"job":{"kind":"plank","owner":owner,"ready":0,"ingredients":{"wood":4},"yield":2}}
	world.state.removed["52,24"]=true
	world.save_path=args[0]
	quit(0 if world.save() else 1)

