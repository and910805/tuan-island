extends SceneTree

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const PLOT:=Vector2i(40,34)
const CORNER:=PLOT+Vector2i.ONE
const PASSWORD:="leaf-mat-network-fixture"
var session:Session
var role:String
var checks:=0
var failures:=0
var notices:Array[bool]=[]

func _initialize()->void:
	run.call_deferred()

func expect(success:bool,label:String)->bool:
	checks+=1
	if not success:
		failures+=1
		push_error(role+": "+label)
	return success

func wait_for(condition:Callable,label:String,seconds:=8.0)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<deadline:
		await create_timer(0.03).timeout
	return expect(bool(condition.call()),label)

func token(who:String)->String:
	return "leaf-mat-network-"+who

func actor(who:String)->Dictionary:
	return session.snapshot.get("players",{}).get(Session._public_actor(token(who)),{})

func piece(tile:Vector2i)->Dictionary:
	return session.snapshot.get("ground",{}).get(World.key(tile),{})

func act(action:String,tile:Vector2i,extra:String,success:bool)->bool:
	var next:=notices.size()
	session.perform(action,tile,extra)
	if not await wait_for(func():return notices.size()>next,"Receives reply to "+action):return false
	return expect(notices[next]==success,"Server enforces permission for "+action)

func serve(port:int)->void:
	var path:="user://leaf-mat-network-%d.json"%OS.get_process_id()
	if not expect(session.host(port,"地墊連線驗收",path,PASSWORD,"127.0.0.1",true,"websocket")==OK,"Dedicated WebSocket room starts"):return
	var world:World=session.world
	world.add_player(token("owner"),"地墊主人",Vector2(40.5,33.5))
	world.add_player(token("guest"),"朋友",Vector2(41.5,33.5))
	var person:Dictionary=world.state.players[token("owner")]
	person.inventory.merge({"fiber":12,"chime_herb":3},true)
	for offset:Vector2i in Industry.SQUARE_CELLS:
		world.state.removed[World.key(PLOT+offset)]=true
	if await wait_for(func():return session.peers.size()==2,"Both independent clients join",15):
		await wait_for(func():return session.peers.is_empty(),"Both clients finish their checks",30)
	expect(world.state.ground.is_empty() and person.inventory.fiber==12 and person.inventory.chime_herb==3,"Server has zero parts and exactly one refunded recipe")
	expect(session.shutdown(),"Server saves on shutdown")
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func exercise(port:int)->void:
	session.profile.token=token(role)
	session.notice.connect(func(_message:String,success:bool):notices.append(success))
	if not expect(session.join("ws://127.0.0.1:%d"%port,port,role,PASSWORD)==OK,"WebSocket client tries to join"):return
	if not await wait_for(func():return not actor("owner").is_empty() and not actor("guest").is_empty(),"Clients can see one another"):return
	if role=="owner":
		if not await act("build",PLOT,Industry.LEAF_MAT,true):return
		if not await wait_for(func():return piece(CORNER).get("leaf_mat_part")==3,"Owner sees the far corner after the build"):return
		if not await act(Industry.MAT_SHADE_ACTION,CORNER,"dark",true):return
		if not await wait_for(func():return piece(PLOT).get("leaf_mat_shade")=="dark","Owner observes the synchronized shade"):return
		if not await wait_for(func():return float(actor("guest").get("y",0))>34.3,"Guest has walked onto the shared mat"):return
		if not await act("remove",CORNER,"",true):return
		await wait_for(func():return piece(CORNER).is_empty(),"Owner sees the entire rug removed")
	else:
		if not await wait_for(func():return piece(PLOT).get("leaf_mat_shade")=="dark","Guest observes the owner's recolor"):return
		expect(piece(CORNER).get("owner")==Session._public_actor(token("owner")) and piece(CORNER).get("leaf_mat_part")==3,"Guest sees matching owner and footprint in the public snapshot")
		if not await act(Industry.MAT_SHADE_ACTION,CORNER,"light",false):return
		if not await act("remove",CORNER,"",false):return
		session.input_direction(Vector2.DOWN)
		if not await wait_for(func():return float(actor("guest").get("y",0))>34.3,"Guest walks on the mat with standard network movement"):return
		session.input_direction(Vector2.ZERO)
		await wait_for(func():return piece(PLOT).is_empty() and piece(CORNER).is_empty(),"Guest sees complete removal")

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2 or args[0] not in ["server","owner","guest"]:
		quit(1)
		return
	role=args[0]
	var island:=Node2D.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	if role=="server":await serve(int(args[1]))
	else:
		await exercise(int(args[1]))
		session.shutdown()
	print("LEAF_MAT_NETWORK_TESTS role=%s checks=%d failures=%d"%[role,checks,failures])
	quit(int(failures>0))
