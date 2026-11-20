extends SceneTree

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Table:=World.INDUSTRY
const SEAT:=World.RESIDENT_GOALS.MASTER_BENCH_SEAT
const SITE:=Vector2i(40,34)
const PASSWORD:="mushroom-table-test"
const ROLES:=["alpha","beta","gamma","delta"]
var session:Session
var role:String
var kind:=Table.MUSHROOM_TABLE
var meal:="soup"
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
	return kind+"-network-"+which

func seating(which:String)->int:
	var pose:Dictionary=actor(which).get(SEAT,{})
	return int(pose.side) if pose.get("cell")==World.key(SITE) else -1

func portions()->int:
	return int(session.snapshot.get("objects",{}).get(World.key(SITE),{}).get("items",{}).get(meal,0))

func request(verb:String,arg:String,expected:bool)->bool:
	var target:=notices.size()
	session.perform(verb,SITE+Vector2i.RIGHT,arg)
	if not await wait_for(func():return notices.size()>target,"Receives action result"):return false
	return expect(notices[target]==expected,"Action result matches authoritative seat and meal state")

func serve(port:int)->void:
	var path:="user://%s-network-%d.json"%[kind,OS.get_process_id()]
	if not expect(session.host(port,World.BUILD[kind].name,path,PASSWORD,"127.0.0.1",true,"websocket")==OK,"Starts a dedicated WebSocket server"):return
	var world:World=session.world
	for index in ROLES.size():
		var id:=token(ROLES[index])
		world.add_player(id,ROLES[index],Vector2(39.5+index,33.1))
		world.state.players[id].mine_energy=30
	var owner:Dictionary=world.state.players[token("alpha")]
	owner.inventory.merge(World.BUILD[kind],true)
	owner.inventory.erase("name")
	owner.inventory[meal]=4
	for offset:Vector2i in Table.station_cells(kind):world.state.removed[World.key(SITE+offset)]=true
	if not expect(world.act(token("alpha"),"setup","build",SITE,kind).ok,"Builds the table in the server world"):return
	if await wait_for(func():return session.peers.size()==4,"Four distinct clients join",20.0):
		await wait_for(func():return session.peers.is_empty(),"All four clients finish",20.0)
		var cart:Dictionary=world.state.objects[World.key(SITE)]
		expect(cart.items.is_empty() and int(owner.inventory.get(meal,0))==0,"Exactly four shared portions were consumed")
		for which:String in ROLES:
			expect(int(world.state.players[token(which)].mine_energy)==42,"Each player consumes exactly one meal")
	expect(session.shutdown(),"Server saves and shuts down")
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func exercise(port:int)->void:
	session.profile.token=token(role)
	session.notice.connect(func(_message:String,success:bool):notices.append(success))
	if not expect(session.join("ws://127.0.0.1:%d"%port,port,role,PASSWORD)==OK,"Starts a WebSocket connection"):return
	if not await wait_for(func():return ROLES.all(func(which):return not actor(which).is_empty()),"All four players appear in the snapshot",15.0):return
	if role=="alpha":
		for _index in range(4):
			if not await request(Table.MUSHROOM_SERVE,meal,true):return
		if not await request(Table.MUSHROOM_SIT,"0",true):return
	else:
		if not await wait_for(func():return seating("alpha")==0 and portions()==4,"Guest sees four portions and the occupied first seat"):return
		if not await request(Table.MUSHROOM_SIT,"0",false):return
		if not await request(Table.MUSHROOM_SIT,str(ROLES.find(role)),true):return
	if not await wait_for(func():return ROLES.all(func(which):return seating(which)==ROLES.find(which)),"All four seats are independently occupied"):return
	if not await request(Table.MUSHROOM_EAT,meal,true):return
	if not await wait_for(func():return portions()==0 and int(actor(role).mine_energy)==42,"Shared stock reaches zero; this player ate exactly one portion"):return
	if role=="alpha":
		if not await request(Table.MUSHROOM_EAT,meal,false):return
		if not await request(Table.MUSHROOM_SIT,"leave",true):return
		await wait_for(func():return seating("alpha")==-1,"Owner can leave after dining")
	else:
		await wait_for(func():return actor("alpha").is_empty() or seating("alpha")==-1,"Guest sees owner leave the table after the meal")
	session.shutdown()

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size() not in [2,3] or args[0] not in ["server"]+ROLES or (args.size()==3 and args[2]!="tea"):
		quit(1)
		return
	if args.size()==3:
		kind=Table.BAMBOO_TEA_TABLE
		meal="tea_pudding"
	role=args[0]
	var island:=Node2D.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	if role=="server":await serve(int(args[1]))
	else:await exercise(int(args[1]))
	var check_name:="BAMBOO_TEA_TABLE_NETWORK_TESTS" if kind==Table.BAMBOO_TEA_TABLE else "MUSHROOM_TABLE_NETWORK_TESTS"
	print("%s role=%s checks=%d failures=%d"%[check_name,role,checks,failures])
	quit(int(failures>0))
