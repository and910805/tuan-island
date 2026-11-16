extends SceneTree
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const ACTOR := "auto-freight-net-alpha"
const SOURCE := "26,24"
const TARGET := "40,38"

func _initialize()->void:run.call_deferred()

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args[0]=="seed":
		var world:=World.new()
		world.save_path=args[1]
		world.state.mine_depths.unlocked=5
		world.state.mine_depths.pumped=24
		for role in ["alpha","beta"]:
			var actor:String="auto-freight-net-"+role
			world.add_player(actor,role)
			var person:Dictionary=world.state.players[actor]
			person.region="mine_4"
			person.x=33.5
			person.y=20.5
		world.state.regions.mine_4.objects[SOURCE]={"type":"private_chest","owner":ACTOR,"items":{"copper_ore":8}}
		world.state.objects[TARGET]={"type":"private_chest","owner":ACTOR,"items":{}}
		quit(0 if world.save() else 1)
		return
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	var session:=Session.new()
	island.add_child(session)
	session.profile.token="auto-freight-net-"+args[2]
	if session.join("127.0.0.1",int(args[1]),args[2],"auto-freight-test")!=OK:quit(1);return
	var alpha:=args[2]=="alpha"
	var deadline:=Time.get_ticks_msec()+6000
	while session.own_id.is_empty() and Time.get_ticks_msec()<deadline:await create_timer(.05).timeout
	if session.own_id.is_empty():quit(1);return
	var receipts:Array[Dictionary]=[]
	session.notice.connect(func(message:String,ok:bool):receipts.append({"message":message,"ok":ok}))
	if args[0]=="start":
		while session.snapshot.players.size()<2 and Time.get_ticks_msec()<deadline:await create_timer(.05).timeout
		if session.snapshot.players.size()!=2:quit(1);return
		var config:=JSON.stringify({"source":SOURCE,"target":TARGET,"item":"copper_ore","reserve":1,"batch":4})
		session.perform("mine_auto_config",World.MINES.SERVICE,config)
		await create_timer(.4).timeout
		session.perform("mine_auto_toggle",World.MINES.SERVICE)
		await create_timer(.8).timeout
	var private_data:Dictionary=session.snapshot.get("mine_auto_freight",{})
	var job:Dictionary=session.snapshot.get("mine_freight",{}).get("own_job",{})
	var ok:=false
	if alpha:
		var route:Dictionary=private_data.get("route",{})
		ok=route.get("enabled",false) and int(route.get("batch",0))==4 and int(route.get("reserve",0))==1 and job.get("status")=="transit" and int(job.items.get("copper_ore",0))==4
		ok=ok and (args[0]=="reconnect" or receipts.size()==2 and receipts.all(func(r):return r.ok))
	else:
		ok=private_data.get("route",{})=={} and private_data.get("sources",[])==[] and job.is_empty() and receipts.size()==2 and receipts.all(func(r):return not r.ok)
	if not ok:
		push_error("Unexpected ENet route visibility or receipts %s / %s / %s"%[private_data,job,receipts])
		quit(1)
		return
	print("MINE_AUTO_FREIGHT_ENET_PASS ",args[0]," ",args[2])
	session.shutdown()
	await create_timer(.2).timeout
	quit()
