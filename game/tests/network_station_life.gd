extends SceneTree
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")

func _initialize()->void:run.call_deferred()

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args[0]=="seed":
		var world:=World.new()
		world.save_path=args[1]
		world.state.picnic=true
		for role in ["alpha","beta"]:
			var actor:String="station-net-"+role
			world.add_player(actor,role)
			var person:Dictionary=world.state.players[actor]
			person.region="ruifang"
			person.travel_book.visited.toucheng=true
			person.travel_book.visited.ruifang=true
			person.x=24.5
			person.y=25.5
			person.inventory.plank=2
			if role=="alpha":world.state.station_life.players[actor]={"stage":1}
		quit(0 if world.save() else 1)
		return
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	var session:=Session.new()
	island.add_child(session)
	session.profile.token="station-net-"+args[2]
	if session.join("127.0.0.1",int(args[1]),args[2],"station-test")!=OK:quit(1);return
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
		var cell:=Vector2i(24,25)
		if alpha:
			session.perform("station_repair",cell,"ruifang")
			await create_timer(.3).timeout
			session.perform("station_story",cell,"1")
			session.perform("station_story",cell,"1")
		else:
			session.perform("station_story",cell,"1")
		await create_timer(.6).timeout
	var life:Dictionary=session.snapshot.station_life
	if not life.players.is_empty() or not life.repairs.ruifang or life.own_story.stage!=(2 if alpha else 0):
		push_error("Incorrect station repair or private story state")
		quit(1)
		return
	var inventory:Dictionary=session.snapshot.players[session.own_id].inventory
	if inventory.plank!=(0 if alpha else 2) or inventory.stone!=(2 if alpha else 4):quit(1);return
	print("STATION_ENET_PASS ",args[0]," ",args[2])
	session.shutdown()
	await create_timer(.2).timeout
	quit()
