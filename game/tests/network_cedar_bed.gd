extends SceneTree

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Bed=World.INDUSTRY
const TILE:=Vector2i(40,34)
const OWNER:="cedar-bed-test-owner"
const GUEST:="cedar-bed-test-guest"
const PASSWORD:="cedar-bed-test"
var session:Session
var role:String
var checks:=0
var failures:=0
var results:Array[bool]=[]

func _initialize()->void:run.call_deferred()

func expect(ok:bool,message:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error(role+": "+message)
	return ok

func wait_for(condition:Callable,message:String,seconds:=16.0)->bool:
	var until:=Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<until:
		await create_timer(0.05).timeout
	return expect(bool(condition.call()),message)

func actor(token:String)->Dictionary:
	return session.snapshot.get("players",{}).get(Session._public_actor(token),{})

func serve(port:int)->void:
	var path:="user://cedar-bed-network-%d.json"%OS.get_process_id()
	if not expect(session.host(port,"木床連線驗收",path,PASSWORD,"127.0.0.1",true,"websocket")==OK,"Dedicated server starts"):return
	var world:World=session.world
	world.add_player(OWNER,"木床主人",Vector2(41.5,34.5))
	world.add_player(GUEST,"來訪島民",Vector2(41.5,35.5))
	world.state.players[OWNER].mine_energy=22
	world.state.players[GUEST].mine_energy=33
	world.state.players[OWNER].inventory.merge({"wood":15,"fiber":10},true)
	for tile in [TILE,TILE+Vector2i.DOWN]:world.state.removed[World.key(tile)]=true
	expect(world.act(OWNER,"test-bed","build",TILE,Bed.CEDAR_BED).ok,"Place the bed with the production action")
	world.state.time=720.0
	if await wait_for(func():return session.peers.size()==2,"Both clients connected"):
		await wait_for(func():return session.peers.is_empty(),"Both clients finished",32)
	expect(world.state.players[OWNER].mine_energy==100 and world.state.players[GUEST].mine_energy==33,"Server applied recovery only to the owner")
	expect(world.state.players[OWNER].get(Bed.HOME_REST_FIELD)==World.key(TILE) and not world.state.players[GUEST].has(Bed.HOME_REST_FIELD),"Server kept one private preference")
	expect(int(world.state.get("day",1))==1 and absf(float(world.state.time)-720.0)<60.0,"The room stayed on the same day and time band")
	expect(session.shutdown(),"Server saves cleanly")
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func exercise(port:int)->void:
	var token:=OWNER if role=="owner" else GUEST
	session.profile.token=token
	session.notice.connect(func(_message:String,success:bool):results.append(success))
	if not expect(session.join("ws://127.0.0.1:%d"%port,port,role,PASSWORD)==OK,"WebSocket join starts"):return
	if not await wait_for(func():return not actor(OWNER).is_empty() and not actor(GUEST).is_empty(),"Both clients see the players"):return
	var objects:Dictionary=session.snapshot.objects
	expect(objects.get(World.key(TILE),{}).get("type")==Bed.CEDAR_BED and World.station_anchor(objects,TILE+Vector2i.DOWN)==TILE,"Both bed tiles arrive over WebSocket")
	if token==OWNER:
		session.perform(Bed.CEDAR_BED,TILE+Vector2i.DOWN,"mark")
		if not await wait_for(func():return actor(OWNER).get(Bed.HOME_REST_FIELD)==World.key(TILE),"Owner sees their marked bed"):return
		session.perform(Bed.CEDAR_BED,TILE,"rest")
		if not await wait_for(func():return int(actor(OWNER).get("mine_energy",0))==100,"Owner sees recovered energy"):return
		await wait_for(func():return actor(GUEST).is_empty(),"Owner stays online until the guest finishes")
	else:
		if not await wait_for(func():return int(actor(OWNER).get("mine_energy",0))==100,"Guest sees the owner finish resting"):return
		expect(not actor(OWNER).has(Bed.HOME_REST_FIELD),"Guest cannot see the owner's preference")
		expect(int(actor(GUEST).get("mine_energy",0))==33,"The guest keeps their own energy")
		var start:=results.size()
		session.perform(Bed.CEDAR_BED,TILE+Vector2i.DOWN,"rest")
		if await wait_for(func():return results.size()>start,"Guest request receives a reply"):
			expect(not results[start],"Guest rest on another player's bed is refused")

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
	print("CEDAR_BED_NETWORK role=%s checks=%d failures=%d"%[role,checks,failures])
	quit(int(failures>0))
