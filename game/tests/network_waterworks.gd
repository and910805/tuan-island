extends SceneTree
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")

func _initialize()->void:run.call_deferred()

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args[0]=="seed":
		var world:=World.new()
		world.save_path=args[1]
		world.state.mine_depths.unlocked=4
		world.state.mine_depths.pumped=24
		for role in ["alpha","beta"]:
			var actor:String="waterworks-net-"+role
			world.add_player(actor,role)
			var person:Dictionary=world.state.players[actor]
			person.region="lanyang"
			person.x=12.5
			person.y=20.5
			person.inventory.copper_ore=5
		var machine:Dictionary=World.WATERWORKS.fresh()
		machine.merge({"type":"waterworks","owner":"waterworks-net-alpha"})
		world.state.regions.lanyang.objects["13,20"]=machine
		quit(0 if world.save() else 1)
		return
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	var session:=Session.new()
	island.add_child(session)
	session.profile.token="waterworks-net-"+args[2]
	if session.join("127.0.0.1",int(args[1]),args[2],"waterworks-test")!=OK:quit(1);return
	var deadline:=Time.get_ticks_msec()+5000
	while session.own_id.is_empty() and Time.get_ticks_msec()<deadline:await create_timer(.05).timeout
	if session.own_id.is_empty():quit(1);return
	var alpha:=args[2]=="alpha"
	if args[0]=="start":
		while session.snapshot.players.size()<2 and Time.get_ticks_msec()<deadline:await create_timer(.05).timeout
		if session.snapshot.players.size()!=2:
			push_error("Expected two co-located clients before travelling")
			quit(1)
			return
		await create_timer(.2).timeout
		var cell:=Vector2i(13,20)
		session.perform("waterworks_feed",cell,"copper_ore:5")
		if not alpha:session.perform("waterworks_toggle",cell)
		await create_timer(.8).timeout
	var machine:Dictionary=session.snapshot.objects["13,20"]
	var inventory:Dictionary=session.snapshot.players[session.own_id].inventory
	if machine.input.copper_ore!=5 or machine.enabled or inventory.copper_ore!=(0 if alpha else 5):
		push_error("Unexpected machine or inventory: %s/%s/%s (%s,%s)" % [machine.input.copper_ore,machine.enabled,inventory.copper_ore,session.snapshot.players[session.own_id].x,session.snapshot.players[session.own_id].y])
		quit(1)
		return
	print("WATERWORKS_ENET_PASS ",args[0]," ",args[2])
	session.shutdown()
	await create_timer(.2).timeout
	quit()
