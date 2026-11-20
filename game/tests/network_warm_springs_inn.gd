extends SceneTree

const Session=preload("res://scripts/session.gd")
const Springs=preload("res://scripts/warm_springs.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const Music=preload("res://scripts/scene_music.gd")
const ROOM_KEY:="inn-network-test"
const FIRST_CHAIR:=Vector2i(67,24)
const SECOND_CHAIR:=Vector2i(66,25)

var session:Session
var role:String
var checks:=0
var failures:=0
var notices:Array[bool]=[]

func _initialize() -> void:
	run.call_deferred()

func expect(condition:bool,message:String) -> bool:
	checks+=1
	if condition:return true
	failures+=1
	push_error("%s: %s"%[role,message])
	return false

func wait_for(condition:Callable,message:String,seconds:=6.0) -> bool:
	var until:=Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<until:
		await create_timer(0.02).timeout
	return expect(bool(condition.call()),message)

func token(which:String) -> String:
	return "warm-springs-inn-network-"+which

func person(which:String) -> Dictionary:
	return session.snapshot.get("players",{}).get(Session._public_actor(token(which)),{})

func chair_state(cell:Vector2i) -> String:
	return "%s:%d,%d"%[Springs.INN_USE,cell.x,cell.y]

func seated(which:String,cell:Vector2i) -> bool:
	return person(which).get(Springs.REST_SEAT_KEY)==chair_state(cell)

func track(which:String) -> String:
	return Music.local_track(session.snapshot,str(session.snapshot.get("region_id","")),person(which))

func action(which:String,cell:Vector2i,expected:bool) -> bool:
	var target:=notices.size()+1
	session.perform(which,cell)
	if not await wait_for(func():return notices.size()>=target,"Receives reply for "+which):return false
	return expect(notices[target-1]==expected,"Expected result for "+which)

func serve(port:int) -> void:
	var path:="user://inn-network-%d.json"%OS.get_process_id()
	if not expect(session.host(port,"旅舍驗收",path,ROOM_KEY,"127.0.0.1",true,"websocket")==OK,"Starts a dedicated WebSocket server"):return
	for which in ["alpha","beta"]:
		session.world.add_player(token(which),which)
		var actor:Dictionary=session.world.state.players[token(which)]
		actor.region=Springs.REGION
		actor.x=Springs.INN_DOOR.x+0.5
		actor.y=Springs.INN_DOOR.y+0.5
		actor.bonds={"nuannuan":{"points":1,"gift_day":-1,"talk_day":-1}}
	if await wait_for(func():return session.peers.size()==2,"Both real clients connect",12.0):
		await wait_for(func():return session.peers.is_empty(),"Both real clients finish and disconnect",18.0)
	expect(session.world.state.players[token("alpha")].get(Goals.INN_CLEAR_KEY,false) and not session.world.state.players[token("beta")].has(Goals.INN_CLEAR_KEY),"Only Alpha's cleanup is saved on the server")
	expect(session.shutdown(),"Server writes final state cleanly")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func exercise(port:int) -> void:
	session.profile.token=token(role)
	session.notice.connect(func(_message:String,success:bool):notices.append(success))
	if not expect(session.join("ws://127.0.0.1:%d"%port,port,role,ROOM_KEY)==OK,"Starts WebSocket join"):return
	if not await wait_for(func():return not person("alpha").is_empty() and not person("beta").is_empty(),"Both players are visible in the shared snapshot"):return
	expect(Springs.entrance_progress(session.snapshot)==Springs.Entrance.LEAVES,"The visible entrance begins unswept")
	if role=="alpha":
		if not await action(Goals.INN_CLEAR_ACTION,Springs.INN_DOOR,true):return
		if not await wait_for(func():return Springs.entrance_progress(session.snapshot)==Springs.Entrance.SWEPT,"Alpha sees the swept entrance"):return
	if not await action(Springs.INN_PORTAL,Springs.INN_DOOR,true):return
	if not await wait_for(func():return Springs.in_inn(person("alpha")) and Springs.in_inn(person("beta")),"Both players independently enter the inn"):return
	expect(track(role)==Music.INN_TRACK,"Only the local indoor position selects the inn track")
	if role=="alpha":
		if not await action(Springs.INN_USE,FIRST_CHAIR,true):return
		if not await wait_for(func():return seated("alpha",FIRST_CHAIR) and seated("beta",SECOND_CHAIR),"Alpha observes two assigned seats"):return
		if not await wait_for(func():return not person("beta").is_empty() and not Springs.in_inn(person("beta")),"Beta exits while alpha stays"):return
		expect(seated("alpha",FIRST_CHAIR) and track("alpha")==Music.INN_TRACK,"Beta exiting does not move alpha or change alpha's music")
	else:
		if not await wait_for(func():return seated("alpha",FIRST_CHAIR),"Beta sees alpha's seat before trying it"):return
		expect(Springs.entrance_progress(session.snapshot)==Springs.Entrance.LEAVES,"Alpha's cleanup does not advance Beta's story or preview")
		if not await action(Springs.INN_USE,FIRST_CHAIR,false):return
		if not await action(Springs.INN_USE,SECOND_CHAIR,true):return
		if not await wait_for(func():return seated("alpha",FIRST_CHAIR) and seated("beta",SECOND_CHAIR),"Beta observes both seats occupied"):return
		session.input_direction(Vector2.DOWN)
		if not await wait_for(func():return not seated("beta",SECOND_CHAIR),"A network movement releases beta's chair"):return
		session.input_direction(Vector2.ZERO)
		if not await action(Springs.INN_PORTAL,Springs.INN_EXIT,true):return
		if not await wait_for(func():return not Springs.in_inn(person("beta")),"Beta returns to the exterior"):return
		expect(seated("alpha",FIRST_CHAIR) and track("beta").is_empty(),"Beta's client sees alpha still seated and selects the outdoor base track")
		await create_timer(0.3).timeout
	session.shutdown()

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2 or args[0] not in ["server","alpha","beta"]:
		quit(1)
		return
	role=args[0]
	var island:=Node2D.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	if role=="server":await serve(int(args[1]))
	else:await exercise(int(args[1]))
	print("INN_NETWORK_TESTS role=%s checks=%d failures=%d"%[role,checks,failures])
	quit(int(failures>0))
