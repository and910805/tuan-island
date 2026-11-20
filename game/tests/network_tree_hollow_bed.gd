extends SceneTree

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Bed:=World.INDUSTRY
const SEAT:=World.RESIDENT_GOALS.MASTER_BENCH_SEAT
const SITE:=Vector2i(40,34)
const PASSWORD:="hollow-bed-test"
var session:Session
var role:String
var checks:=0
var failures:=0
var notices:Array[bool]=[]

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
	return "hollow-bed-network-"+which

func resting(which:String)->bool:
	return actor(which).get(SEAT,{}).get("cell")==World.key(SITE)

func rest(expected:bool)->bool:
	var target:=notices.size()
	session.perform(Bed.HOLLOW_REST,SITE+Vector2i.RIGHT)
	if not await wait_for(func():return notices.size()>target,"Receives a rest result"):return false
	return expect(notices[target]==expected,"Rest result matches the authoritative occupancy")

func serve(port:int)->void:
	var path:="user://hollow-bed-network-%d.json"%OS.get_process_id()
	if not expect(session.host(port,"樹洞小床驗收",path,PASSWORD,"127.0.0.1",true,"websocket")==OK,"Starts a dedicated WebSocket server"):return
	var world:World=session.world
	for which:String in ["alpha","beta"]:
		world.add_player(token(which),which,Vector2(41.5,33.5 if which=="alpha" else 32.5))
		world.state.players[token(which)].mine_energy=25
	world.state.players[token("alpha")].inventory.merge({"hardwood":18,"cotton_cloth":5,"fiber":8},true)
	for offset:Vector2i in Bed.SQUARE_CELLS:world.state.removed[World.key(SITE+offset)]=true
	if not expect(world.act(token("alpha"),"setup-bed","build",SITE,Bed.HOLLOW_BED).ok,"Builds the four-tile bed"):return
	if await wait_for(func():return session.peers.size()==2,"Two distinct clients connect",15.0):
		await wait_for(func():return session.peers.is_empty(),"Both clients finish and disconnect",20.0)
	expect(session.shutdown(),"Server closes and saves cleanly")
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func exercise(port:int)->void:
	session.profile.token=token(role)
	session.notice.connect(func(_message:String,success:bool):notices.append(success))
	if not expect(session.join("ws://127.0.0.1:%d"%port,port,role,PASSWORD)==OK,"Starts a WebSocket connection"):return
	if not await wait_for(func():return not actor("alpha").is_empty() and not actor("beta").is_empty(),"Both players are visible"):return
	if role=="alpha":
		if not await rest(true):return
		if not await wait_for(func():return resting("alpha") and int(actor("alpha").get("mine_energy",0))==100,"First sleeper receives the pose and recovery"):return
		if not await wait_for(func():return float(actor("beta").get("y",0.0))<32.25,"Guest observed the occupied bed"):return
		if not await rest(true):return
		if not await wait_for(func():return resting("beta"),"Second sleeper is visible on alpha's client"):return
		if not await wait_for(func():return actor("beta").is_empty(),"Guest disconnects while resting"):return
		if not await rest(true):return
		await wait_for(func():return resting("alpha"),"Disconnect frees the bed for another player")
	else:
		if not await wait_for(func():return resting("alpha"),"Guest sees the sleeping owner"):return
		if not await rest(false):return
		session.input_direction(Vector2(-0.3,-1.0))
		if not await wait_for(func():return float(actor("beta").get("y",0.0))<32.25,"Guest acknowledges by walking a few steps"):return
		session.input_direction(Vector2.ZERO)
		if not await wait_for(func():return not resting("alpha"),"Owner gets up"):return
		if not await rest(true):return
		if await wait_for(func():return resting("beta"),"Guest can use the free bed"):
			await create_timer(0.5).timeout
	session.shutdown()

func run()->void:
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
	print("HOLLOW_BED_NETWORK_TESTS role=%s checks=%d failures=%d"%[role,checks,failures])
	quit(int(failures>0))
