extends SceneTree

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Kind:=World.INDUSTRY.ACORN_CABINET
const Access:=World.INDUSTRY.CABINET_ACCESS
const SITE:=Vector2i(42,34)
const PASSWORD:="acorn-cabinet-fixture"
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
	return "cabinet-network-"+who

func actor(who:String)->Dictionary:
	return session.snapshot.get("players",{}).get(Session._public_actor(token(who)),{})

func cabinet()->Dictionary:
	return session.snapshot.get("objects",{}).get(World.key(SITE),{})

func act(action:String,extra:String,success:bool)->bool:
	var reply:=notices.size()
	session.perform(action,SITE,extra)
	if not await wait_for(func():return notices.size()>reply,"Receives "+action+" reply"):return false
	return expect(notices[reply]==success,"Server applies expected rights for "+action)

func serve(port:int)->void:
	var path:="user://acorn-cabinet-network-%d.json"%OS.get_process_id()
	if not expect(session.host(port,"橡果櫃多人驗收",path,PASSWORD,"127.0.0.1",true,"websocket")==OK,"Dedicated room starts"):return
	var world:World=session.world
	world.add_player(token("owner"),"櫃主",Vector2(42.5,33.4))
	world.add_player(token("guest"),"來訪朋友",Vector2(43.5,33.4))
	world.state.players[token("owner")].inventory.merge({"hardwood":16,"fiber":4,"wood":3},true)
	world.state.players[token("guest")].inventory.merge({"wood":0,"stone":3},true)
	world.state.removed[World.key(SITE)]=true
	expect(world.act(token("owner"),"build","build",SITE,Kind).ok,"Builds using normal rules")
	expect(world.act(token("owner"),"stock","deposit_all",SITE,"wood").ok,"Stocks the new private cabinet")
	if await wait_for(func():return session.peers.size()==2,"Both independent clients join",15):
		await wait_for(func():return session.peers.is_empty(),"Both clients disconnect",32)
	var box:Dictionary=world.state.objects[World.key(SITE)]
	expect(box.items=={"wood":2,"stone":1} and not box.get("cabinet_shared",false),"The authoritative closed cabinet contains the exact remaining stock")
	expect(world.state.players[token("guest")].inventory.wood==1 and world.state.players[token("guest")].inventory.stone==2,"Guests receive and spend only the shared transfers")
	expect(session.shutdown(),"Server closes cleanly")
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func exercise(port:int)->void:
	session.profile.token=token(role)
	session.notice.connect(func(_message:String,success:bool):notices.append(success))
	if not expect(session.join("ws://127.0.0.1:%d"%port,port,role,PASSWORD)==OK,"Joins room with the native client protocol"):return
	if not await wait_for(func():return cabinet().get("type")==Kind and not actor("guest").is_empty(),"Cabinet and guest load"):return
	if role=="owner":
		expect(cabinet().items.get("wood")==3 and not cabinet().get("locked",false),"Owner can see the initial private stack")
		if not await wait_for(func():return float(actor("guest").get("y",0))>33.7,"Guest has attempted private access"):return
		if not await act(Access,"island",true):return
		if not await wait_for(func():return cabinet().items.get("stone")==1,"Guest deposits are synchronized to the owner"):return
		if not await act(Access,"owner",true):return
		await wait_for(func():return not cabinet().get("cabinet_shared",false) and actor("guest").is_empty(),"Owner sees access revoked and guest completed")
	else:
		expect(cabinet().get("locked",false) and cabinet().items.is_empty(),"Private data is redacted on the remote client")
		if not await act("withdraw","wood",false):return
		if not await act(Access,"island",false):return
		session.input_direction(Vector2.DOWN)
		if not await wait_for(func():return float(actor("guest").get("y",0))>33.7,"Acknowledges checked private mode"):return
		session.input_direction(Vector2.ZERO)
		if not await wait_for(func():return cabinet().get("cabinet_shared",false) and cabinet().items.get("wood")==3,"Guest sees contents after sharing"):return
		if not await act("withdraw_exact","wood:1",true):return
		if not await act("deposit_exact","stone:1",true):return
		if not await wait_for(func():return cabinet().get("locked",false) and cabinet().items.is_empty(),"Revocation clears the guest's next snapshot"):return
		await act("withdraw","wood",false)

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2 or args[0] not in ["owner","guest","server"]:
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
	print("ACORN_CABINET_NETWORK role=%s checks=%d failures=%d"%[role,checks,failures])
	quit(int(failures>0))
