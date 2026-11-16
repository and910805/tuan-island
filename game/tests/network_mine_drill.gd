extends SceneTree
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")

func _initialize()->void:run.call_deferred()

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args[0]=="seed":
		var world:=World.new()
		world.save_path=args[1]
		world.state.mine_depths.unlocked=5
		world.state.mine_depths.pumped=24
		for role in ["alpha","beta"]:
			var actor:String="drill-net-"+role
			world.add_player(actor,role)
			var person:Dictionary=world.state.players[actor]
			person.region="mine_4"
			person.x=27.5
			person.y=24.5
			person.inventory.charcoal=5
		var machine:Dictionary=World.MINE_DRILL.fresh(0)
		machine.merge({"type":"mine_drill","owner":"drill-net-alpha"})
		world.state.regions.mine_4.objects["28,24"]=machine
		quit(0 if world.save() else 1)
		return
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	var session:=Session.new()
	island.add_child(session)
	session.profile.token="drill-net-"+args[2]
	if session.join("127.0.0.1",int(args[1]),args[2],"drill-test")!=OK:quit(1);return
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
		var cell:=Vector2i(28,24)
		session.perform("mine_drill_feed",cell,"5")
		if not alpha:session.perform("mine_drill_toggle",cell)
		await create_timer(.8).timeout
	var machine:Dictionary=session.snapshot.objects["28,24"]
	var inventory:Dictionary=session.snapshot.players[session.own_id].inventory
	if machine.fuel!=5 or machine.enabled or inventory.charcoal!=(0 if alpha else 5):
		push_error("Unexpected machine or inventory: %s/%s/%s (%s,%s)" % [machine.fuel,machine.enabled,inventory.charcoal,session.snapshot.players[session.own_id].x,session.snapshot.players[session.own_id].y])
		quit(1)
		return
	print("MINE_DRILL_ENET_PASS ",args[0]," ",args[2])
	session.shutdown()
	await create_timer(.2).timeout
	quit()
