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
			var actor:String="transit-net-"+role
			world.add_player(actor,role)
			world.state.players[actor].x=46.5
			world.state.players[actor].y=30.5
		quit(0 if world.save() else 1)
		return
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	var session:=Session.new()
	island.add_child(session)
	session.profile.token="transit-net-"+args[2]
	if session.join("127.0.0.1",int(args[1]),args[2],"transit-test")!=OK:quit(1);return
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
		for id in session.snapshot.players:
			if id!=session.own_id and session.snapshot.players[id].has("travel_book"):
				push_error("Travel book exposed to another client")
				quit(1)
				return
		await create_timer(.2).timeout
		if alpha:
			session.perform("transit",Vector2i(47,30),"toucheng")
			await create_timer(.35).timeout
			session.request_action.rpc_id(1,1000,"transit",Vector2i(12,25),"home","toucheng",0)
		else:
			session.perform("transit",Vector2i(47,30),"jinguashi")
		await create_timer(.6).timeout
	var region:String="toucheng" if alpha else "home"
	var person:Dictionary=session.snapshot.players[session.own_id]
	if session.snapshot.region_id!=region or int(person.travel_epoch)!=int(alpha) or person.travel_book.visited.has("toucheng")!=alpha:
		push_error("Unexpected region, epoch or private travel book")
		quit(1)
		return
	for id in session.snapshot.players:
		if id!=session.own_id and session.snapshot.players[id].has("travel_book"):quit(1);return
	print("TRANSIT_ENET_PASS ",args[0]," ",args[2])
	session.shutdown()
	await create_timer(.2).timeout
	quit()
