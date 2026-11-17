extends SceneTree

const World=preload("res://scripts/world.gd")
const Session=preload("res://scripts/session.gd")
const Chapter=World.CHAPTER_ONE
const KEY:="wangan-onboarding-test"
const PLOTS:={"alpha":Vector2i(51,28),"beta":Vector2i(52,28)}

var role:String
var session:Session
var island:Node2D
var checks:=0
var failures:=0
var notices:Array[bool]=[]

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->bool:
	checks+=1
	if ok:return true
	failures+=1
	push_error("%s: %s"%[role,message])
	return false

func wait_for(condition:Callable,message:String,seconds:=7.0)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<deadline:
		await create_timer(0.03).timeout
	return expect(bool(condition.call()),message)

func token(which:String)->String:
	return "wangan-network-onboarding-"+which

func player(which:String)->Dictionary:
	return session.snapshot.get("players",{}).get(Session._public_actor(token(which)),{})

func stage()->String:
	return str(Chapter.first_crop_step(session.snapshot,session.own_id).get("id",""))

func request(action:String,cell:Vector2i,extra:="")->bool:
	var target:=notices.size()
	session.perform(action,cell,extra)
	if not await wait_for(func():return notices.size()>target,"Server replies to "+action):return false
	return expect(notices[target],action+" succeeds")

func serve(port:int)->void:
	var path:="user://wangan-network-%d.json"%OS.get_process_id()
	if not expect(session.host(port,"望安驗收",path,KEY,"127.0.0.1",true,"websocket")==OK,"Dedicated world accepts WebSocket peers"):return
	if await wait_for(func():return session.peers.size()==2,"Two new clients are admitted",12.0):
		for which:String in PLOTS:
			session.world.state.crops[World.key(PLOTS[which])]={
				"owner":token(which),"kind":"radish","wet":true,"growth":float(World.CROPS.radish.time),"remaining":1,
			}
		for peer in session.peers:session._send_snapshot(peer)
		await wait_for(func():return not session.world.state.players[token("beta")].has(Chapter.PERSONAL_START),"Beta completes the remaining personal lesson after reconnecting",18.0)
		await wait_for(func():return session.peers.is_empty(),"Both clients finish and disconnect",22.0)
		var state:Dictionary=session.world.state
		expect(state.chapter_one.shipped and state.chapter_one.harvests.is_empty(),"The shared chapter advances exactly once and can discard its harvest list")
		for which:String in PLOTS:
			var record:Dictionary=state.players[token(which)]
			expect(not record.has(Chapter.PERSONAL_START) and int(record.coins)==120+int(World.CROPS.radish.price),"Each connected client completed its own shipment")
	expect(session.shutdown(),"Server closes and saves")
	var saved:=World.new()
	expect(saved.load_world(path) and saved.state.chapter_one.shipped
		and not saved.state.players.get(token("beta"),{}).has(Chapter.PERSONAL_START),"The shared and individual completion survive server reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func approach_bin(bin:Vector2i)->bool:
	var deadline:=Time.get_ticks_msec()+6500
	var stop_x:=bin.x+2.5
	while float(player(role).get("x",80.0))>stop_x and Time.get_ticks_msec()<deadline:
		session.input_direction(Vector2.LEFT)
		await create_timer(0.09).timeout
	session.input_direction(Vector2.ZERO)
	var actor:=player(role)
	return expect(Vector2(actor.x,actor.y).distance_to(Vector2(bin)+Vector2(0.5,0.5))<3.2,"Real movement from the dock reaches the shipping bin")

func join(port:int)->bool:
	session.profile.token=token(role)
	session.notice.connect(func(_message:String,success:bool):notices.append(success))
	return expect(session.join("ws://127.0.0.1:%d"%port,port,role,KEY)==OK,"Joins the dedicated world")

func exercise(port:int)->void:
	if not join(port):return
	if not await wait_for(func():return not player("alpha").is_empty() and not player("beta").is_empty(),"Receives both players"):return
	var actor:=player(role)
	expect(Vector2(actor.x,actor.y)==World.WANGAN_COAST.FERRY_LANDING,"The actual received spawn is on the dock")
	expect(actor.get(Chapter.PERSONAL_START,false),"The new client receives its personal lesson")
	var other:="beta" if role=="alpha" else "alpha"
	expect(not player(other).has(Chapter.PERSONAL_START),"Another client's lesson flag is private")
	var plot:Vector2i=PLOTS[role]
	if not await wait_for(func():return session.snapshot.get("crops",{}).has(World.key(plot)),"Receives the ripe crop fixture"):return
	if not await request("harvest",plot):return
	if not await wait_for(func():return stage()=="ship","The player's harvest advances the personal guide"):return
	var bin:=World.SHIPPING.cell_for(session.snapshot)
	if not await approach_bin(bin):return
	if role=="alpha":
		if not await wait_for(func():return int(player("beta").get("harvests",0))>0,"Both crops are harvested before first shipment"):return
	else:
		if not await wait_for(func():return session.snapshot.get("chapter_one",{}).get("shipped",false),"Beta receives the shared chapter update"):return
		expect(stage()=="ship" and player("beta").get(Chapter.PERSONAL_START,false),"Beta's own shipping guide survives Alpha's shipment")
		session.shutdown()
		island.remove_child(session)
		session.queue_free()
		await create_timer(0.3).timeout
		session=Session.new()
		island.add_child(session)
		if not join(port):return
		if not await wait_for(func():return stage()=="ship","The shipping step resumes on a new WebSocket connection"):return
		var resumed:=player("beta")
		expect(Vector2(resumed.x,resumed.y).distance_to(Vector2(bin)+Vector2(0.5,0.5))<3.2,"The reconnect restores Beta's place near the bin")
	var payload:=JSON.stringify([[["radish",1]],int(World.CROPS.radish.price)])
	if not await request("ship",bin,payload):return
	await wait_for(func():return session.snapshot.get("chapter_one",{}).get("shipped",false) and stage().is_empty(),"The received snapshot finishes this player's lesson")

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2 or args[0] not in ["server","alpha","beta"]:
		quit(1)
		return
	role=args[0]
	island=Node2D.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	if role=="server":await serve(int(args[1]))
	else:
		await exercise(int(args[1]))
		session.shutdown()
	print("WANGAN_NETWORK_TESTS role=%s checks=%d failures=%d"%[role,checks,failures])
	quit(int(failures>0))
