extends SceneTree

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const ARCH:=Industry.FOREST_ARCH
const SITE:=Vector2i(38,34)
const CENTER:=SITE+Vector2i.RIGHT
const END:=SITE+Vector2i(2,0)
const PASSWORD:="forest-arch-fixture"
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

func navigate(direction:Vector2,reached:Callable,label:String)->bool:
	var deadline:=Time.get_ticks_msec()+7000
	while not reached.call() and Time.get_ticks_msec()<deadline:
		session.input_direction(direction)
		await create_timer(0.04).timeout
	session.input_direction(Vector2.ZERO)
	return expect(bool(reached.call()),label+" at "+str(Vector2(float(actor("guest").get("x",0)),float(actor("guest").get("y",0)))))

func token(who:String)->String:
	return "forest-arch-network-"+who

func actor(who:String)->Dictionary:
	return session.snapshot.get("players",{}).get(Session._public_actor(token(who)),{})

func object(tile:Vector2i)->Dictionary:
	return session.snapshot.get("objects",{}).get(World.key(tile),{})

func act(action:String,tile:Vector2i,extra:String,success:bool)->bool:
	var reply:=notices.size()
	session.perform(action,tile,extra)
	if not await wait_for(func():return notices.size()>reply,"Receives result for "+action):return false
	return expect(notices[reply]==success,"Expected permission for "+action)

func serve(port:int)->void:
	var path:="user://forest-arch-network-%d.json"%OS.get_process_id()
	if not expect(session.host(port,"森林拱門多人驗收",path,PASSWORD,"127.0.0.1",true,"websocket")==OK,"Dedicated server starts"):return
	var world:World=session.world
	world.add_player(token("owner"),"拱門主人",Vector2(40.5,33.1))
	world.add_player(token("guest"),"訪客",Vector2(38.5,35.7))
	world.state.players[token("owner")].inventory.merge({"hardwood":16,"fiber":6,"chime_herb":4},true)
	for offset:Vector2i in Industry.station_cells(ARCH):
		world.state.removed[World.key(SITE+offset)]=true
	if await wait_for(func():return session.peers.size()==2,"Both clients connect",15):
		await wait_for(func():return session.peers.is_empty(),"Both clients completed their checks",27)
	expect(world.state.objects.is_empty() and world.state.players[token("owner")].inventory.hardwood==16,"Server has no orphaned posts and refunded only once")
	expect(session.shutdown(),"Server saves cleanly")
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func exercise(port:int)->void:
	session.profile.token=token(role)
	session.notice.connect(func(_message:String,success:bool):notices.append(success))
	if not expect(session.join("ws://127.0.0.1:%d"%port,port,role,PASSWORD)==OK,"Starts a WebSocket client"):return
	if not await wait_for(func():return not actor("guest").is_empty() and not actor("owner").is_empty(),"Both players are visible"):return
	if role=="owner":
		if not await act("build",SITE,ARCH,true):return
		if not await wait_for(func():return object(END).get("forest_arch_part")==2,"Owner receives the entire footprint"):return
		if not await wait_for(func():return float(actor("guest").get("y",99))<33.9,"Server and owner see the guest cross the center"):return
		if not await act("remove",END,"",true):return
		await wait_for(func():return object(SITE).is_empty() and object(CENTER).is_empty() and object(END).is_empty(),"Owner observes all parts removed")
	else:
		if not await wait_for(func():return object(END).get("forest_arch_part")==2 and Industry.is_arch_passage(object(CENTER)),"Guest receives both posts and the passable center"):return
		if not await act("remove",SITE,"",false):return
		session.input_direction(Vector2.UP)
		await create_timer(0.85).timeout
		session.input_direction(Vector2.ZERO)
		var y:=float(actor("guest").get("y",0))
		expect(y<35.7 and y>=35.0,"Network movement encounters the post collision")
		if not await navigate(Vector2.RIGHT*0.4,func():return float(actor("guest").get("x",0))>=39.39,"Visitor moves to the opening"):return
		if not await navigate(Vector2.UP,func():return float(actor("guest").get("y",99))<33.9,"Network movement crosses the middle opening"):return
		await wait_for(func():return object(SITE).is_empty() and object(CENTER).is_empty() and object(END).is_empty(),"Guest sees synchronized complete removal")

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
	print("FOREST_ARCH_NETWORK role=%s checks=%d failures=%d"%[role,checks,failures])
	quit(int(failures>0))
