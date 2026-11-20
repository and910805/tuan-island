extends SceneTree

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Chair:=World.RESIDENT_GOALS.GARDEN_CHAIR
const Cushion:="indigo_cushion"
const Sit:=World.RESIDENT_GOALS.MASTER_BENCH_SIT
const Seat:=World.RESIDENT_GOALS.MASTER_BENCH_SEAT
const PLOT:=Vector2i(38,34)
const PASSWORD:="garden-chair-test"
var session:Session
var role:String
var chair_kind:=Chair
var checks:=0
var failures:=0
var notices:Array[bool]=[]
var seated_greeting:=false

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->bool:
	checks+=1
	if ok:return true
	failures+=1
	push_error(role+": "+message)
	return false

func wait_for(condition:Callable,message:String,seconds:=7.0)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<deadline:
		await create_timer(0.025).timeout
	return expect(bool(condition.call()),message)

func actor(which:String)->Dictionary:
	return session.snapshot.get("players",{}).get(Session._public_actor(token(which)),{})

func token(which:String)->String:
	return "garden-chair-network-"+which

func seated(which:String,side:=-1)->bool:
	var pose:Dictionary=actor(which).get(Seat,{})
	return pose.get("cell")==World.key(PLOT) and (side<0 or pose.get("side")==side)

func sit(expected:bool,tile:=PLOT)->bool:
	var target:=notices.size()
	session.perform(Sit,tile)
	if not await wait_for(func():return notices.size()>target,"Receives a seat result"):return false
	return expect(notices[target]==expected,"Seat result matches current occupancy")

func serve(port:int)->void:
	var path:="user://copper-chair-network-%d.json"%OS.get_process_id()
	if not expect(session.host(port,"庭園椅連線驗收",path,PASSWORD,"127.0.0.1",true,"websocket")==OK,"Starts a dedicated WebSocket server"):return
	var world:World=session.world
	for which:String in ["alpha","beta"]:
		world.add_player(token(which),which,Vector2(38.5 if which=="alpha" or chair_kind==Cushion else 39.5,33.5))
	var host:Dictionary=world.state.players[token("alpha")]
	host.inventory.copper_ingot=3
	host.inventory.star_mushroom=1
	if chair_kind in World.RESIDENT_GOALS.INDEPENDENT_TWO_SEATS:
		for material:String in World.BUILD[chair_kind]:
			if material!="name":host.inventory[material]=World.BUILD[chair_kind][material]
		world.state.removed[World.key(PLOT+Vector2i.RIGHT)]=true
	if chair_kind==Cushion:
		host.inventory.cotton_cloth=3
		host.inventory.blue_dye=1
		for cell:Vector2i in [PLOT+Vector2i.UP,PLOT,PLOT+Vector2i.DOWN]:
			world.state.removed[World.key(cell)]=true
	if not expect(world.act(token("alpha"),"setup-chair","build",PLOT,chair_kind).ok,"Builds the chair using the normal construction rules"):return
	if chair_kind==Cushion:
		for y:float in [33.5,34.25,34.75,35.25]:
			expect(world.can_stand(Vector2(38.5,y)),"Crossing lane is clear at y=%.2f"%y)
	if await wait_for(func():return session.peers.size()==2,"Two distinct clients connect",15.0):
		await wait_for(func():return session.peers.is_empty(),"Both clients finish and disconnect",24.0)
	expect(session.shutdown(),"The server closes and saves cleanly")
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func exercise(port:int)->void:
	session.profile.token=token(role)
	session.notice.connect(func(_message:String,success:bool):notices.append(success))
	session.emote_received.connect(func(actor_id:String,region:String,caption:String):
		if actor_id==Session._public_actor(token("beta")) and region=="home" and caption==Session.EMOTES.hello and seated("beta"):
			seated_greeting=true)
	if not expect(session.join("ws://127.0.0.1:%d"%port,port,role,PASSWORD)==OK,"Starts a WebSocket connection"):return
	if not await wait_for(func():return not actor("alpha").is_empty() and not actor("beta").is_empty(),"Both characters are visible"):return
	if chair_kind in World.RESIDENT_GOALS.INDEPENDENT_TWO_SEATS:
		await exercise_two_seats()
		session.shutdown()
		return
	if chair_kind==Cushion:
		await exercise_cushion()
		session.shutdown()
		return
	if role=="alpha":
		if not await sit(true):return
		# Beta moves to acknowledge its rejected seat attempt.
		if not await wait_for(func():return float(actor("beta").get("y",0.0))>33.65,"Beta has observed the occupied chair"):return
		if not await sit(true):return
		if not await wait_for(func():return seated("beta"),"Alpha sees the same chair reassigned to beta"):return
		if chair_kind==World.INDUSTRY.WOOD_CHAIR:
			if not await wait_for(func():return seated_greeting,"Alpha receives the visitor's greeting without seeing them stand"):return
		if not await wait_for(func():return actor("beta").is_empty(),"Beta disconnects while seated"):return
		if not await sit(true):return
		await wait_for(func():return seated("alpha"),"Alpha can take the chair again after the disconnection")
	else:
		if not await wait_for(func():return seated("alpha"),"Beta sees alpha already seated"):return
		if not await sit(false):return
		session.input_direction(Vector2.DOWN)
		if not await wait_for(func():return float(actor("beta").get("y",0.0))>33.65,"Movement is visible on the server snapshot"):return
		session.input_direction(Vector2.ZERO)
		if not await wait_for(func():return not seated("alpha"),"Alpha has released the chair"):return
		if not await sit(true):return
		if not await wait_for(func():return seated("beta"),"Both clients can observe beta seated"):return
		if chair_kind==World.INDUSTRY.WOOD_CHAIR:
			session.perform("emote",Vector2i.ZERO,"hello")
			if not await wait_for(func():return seated_greeting,"Visitor can greet from the wooden chair"):return
		await create_timer(0.6).timeout
	session.shutdown()

func exercise_cushion()->void:
	if role=="alpha":
		if not await sit(true):return
		if not await wait_for(func():return float(actor("beta").get("y",0.0))>35.2 and seated("alpha"),"Visitor crosses the cushion while the owner remains seated"):return
		if not await sit(true):return
		await wait_for(func():return seated("beta"),"Visitor can sit after the owner gets up")
	else:
		if not await wait_for(func():return seated("alpha"),"Visitor sees the occupied cushion"):return
		if not await sit(false):return
		# Hold the movement key as a live client does. The server expires a
		# single direction packet after 400 ms, before this crossing ends.
		var deadline:=Time.get_ticks_msec()+7000
		while float(actor("beta").get("y",0.0))<=35.2 and Time.get_ticks_msec()<deadline:
			session.input_direction(Vector2.DOWN)
			await create_timer(0.04).timeout
		session.input_direction(Vector2.ZERO)
		if not expect(float(actor("beta").get("y",0.0))>35.2,"Visitor walks across the occupied tile"):
			print("Visitor position after walking: ",Vector2(actor("beta").get("x",0.0),actor("beta").get("y",0.0)))
			return
		if not await wait_for(func():return not seated("alpha"),"Owner gets up"):return
		if not await sit(true):return
		await wait_for(func():return seated("beta"),"Visitor's seat is confirmed by the server")
		await create_timer(0.6).timeout

func exercise_two_seats()->void:
	var right:=PLOT+Vector2i.RIGHT
	if role=="alpha":
		if not await sit(true):return
		if not await wait_for(func():return seated("alpha",0) and seated("beta",1),"Owner sees both occupants on separate cushions"):return
		if not await sit(true):return
		if not await wait_for(func():return actor("beta").is_empty(),"Visitor disconnects while on the right cushion"):return
		if not await sit(true,right):return
		await wait_for(func():return seated("alpha",1),"Owner can take the right cushion after disconnect")
	else:
		if not await wait_for(func():return seated("alpha",0),"Visitor sees the owner on the left cushion"):return
		if not await sit(false):return
		if not await sit(true,right):return
		if not await wait_for(func():return seated("alpha",0) and seated("beta",1),"Visitor sees both occupants on separate cushions"):return
		await wait_for(func():return not seated("alpha") and seated("beta",1),"Owner getting up leaves the visitor seated")

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size() not in [2,3] or args[0] not in ["server","alpha","beta"]:
		quit(1)
		return
	if args.size()==3 and args[2] not in ["mushroom-stool","wood-chair","cotton-sofa","bamboo-bench","indigo-cushion"]:
		quit(1)
		return
	role=args[0]
	if args.size()==3:
		chair_kind={"mushroom-stool":World.INDUSTRY.MUSHROOM_STOOL,"wood-chair":World.INDUSTRY.WOOD_CHAIR,"cotton-sofa":World.RESIDENT_GOALS.COTTON_SOFA,"bamboo-bench":World.RESIDENT_GOALS.BAMBOO_BENCH,"indigo-cushion":Cushion}[args[2]]
	var island:=Node2D.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	if role=="server":await serve(int(args[1]))
	else:await exercise(int(args[1]))
	var tag:String={World.INDUSTRY.MUSHROOM_STOOL:"MUSHROOM_STOOL_NETWORK_TESTS",World.INDUSTRY.WOOD_CHAIR:"WOOD_CHAIR_NETWORK_TESTS",World.RESIDENT_GOALS.COTTON_SOFA:"COTTON_SOFA_NETWORK_TESTS",World.RESIDENT_GOALS.BAMBOO_BENCH:"BAMBOO_BENCH_NETWORK_TESTS",Cushion:"INDIGO_CUSHION_NETWORK_TESTS"}.get(chair_kind,"COPPER_CHAIR_NETWORK_TESTS")
	print("%s role=%s checks=%d failures=%d"%[tag,role,checks,failures])
	quit(int(failures>0))
