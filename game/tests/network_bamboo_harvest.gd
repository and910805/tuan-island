extends SceneTree

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Bamboo=World.REGIONS.Bamboo
const CUTTER:="ws-bamboo-cutter"
const GUEST:="ws-bamboo-guest"
const PASSWORD:="bamboo-network-test"
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

func wait_for(condition:Callable,message:String,seconds:=14.0)->bool:
	var until:=Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<until:
		await create_timer(0.05).timeout
	return expect(bool(condition.call()),message)

func actor(token:String)->Dictionary:
	return session.snapshot.get("players",{}).get(Session._public_actor(token),{})

func own_amount()->int:
	return int(session.snapshot.get("players",{}).get(session.own_id,{}).get("inventory",{}).get(Bamboo.ITEM,0))

func drop_amount()->int:
	var drop:Dictionary=session.snapshot.get("gather_drops",{}).get(World.key(Bamboo.CLUMPS[0]),{})
	return int(drop.get("items",{}).get(Bamboo.ITEM,0))

func serve(port:int)->void:
	var path:="user://bamboo-network-%d.json"%OS.get_process_id()
	if not expect(session.host(port,"採竹連線驗收",path,PASSWORD,"127.0.0.1",true,"websocket")==OK,"Dedicated server starts"):return
	var world:World=session.world
	var tile:=Bamboo.CLUMPS[0]
	for token in [CUTTER,GUEST]:
		world.add_player(token,token)
		var person:Dictionary=world.state.players[token]
		person.region=Bamboo.REGION
		person.x=float(tile.x)+2.5
		person.y=float(tile.y)+(0.5 if token==CUTTER else 1.5)
	if await wait_for(func():return session.peers.size()==2,"Two clients connected"):
		await wait_for(func():return session.peers.is_empty(),"Both clients finished",30.0)
	expect(int(world.state.players[CUTTER].inventory.get(Bamboo.ITEM,0))==Bamboo.YIELD and not world.state.players[GUEST].inventory.has(Bamboo.ITEM),"Only the player that walked to the drop receives bamboo")
	expect(not Bamboo.ready(world.state,tile),"The server retains the clump cooldown")
	expect(session.shutdown(),"The server saves cleanly")
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func exercise(port:int)->void:
	var token:=CUTTER if role=="cutter" else GUEST
	session.profile.token=token
	session.notice.connect(func(_message:String,success:bool):results.append(success))
	if not expect(session.join("ws://127.0.0.1:%d"%port,port,role,PASSWORD)==OK,"WebSocket join starts"):return
	if not await wait_for(func():return not actor(CUTTER).is_empty() and not actor(GUEST).is_empty(),"Both players are visible in the grove"):return
	var tile:=Bamboo.CLUMPS[0]
	if token==CUTTER:
		session.perform("axe",tile)
		if not await wait_for(func():return drop_amount()==Bamboo.YIELD,"Cutter receives one ground bundle"):return
		expect(own_amount()==0,"The ground bundle still needs pickup")
		if not await wait_for(func():return float(actor(GUEST).get("y",0.0))>float(tile.y)+1.65,"Guest checked the shared cooldown"):return
		session.input_direction(Vector2.LEFT)
		if not await wait_for(func():return own_amount()==Bamboo.YIELD and drop_amount()==0,"Walking picks up one bundle"):return
		session.input_direction(Vector2.ZERO)
		await wait_for(func():return actor(GUEST).is_empty(),"Keep the cutter online while the guest checks the final state")
	else:
		if not await wait_for(func():return drop_amount()==Bamboo.YIELD,"Guest sees the same ground bundle"):return
		expect(not Bamboo.ready(session.snapshot,tile),"Guest and cutter share cooldown state")
		var start:=results.size()
		session.perform("axe",tile)
		if await wait_for(func():return results.size()>start,"Second cut receives a response"):
			expect(not results[start] and drop_amount()==Bamboo.YIELD,"Second cut during cooldown is refused without affecting the ground bundle")
		session.input_direction(Vector2.DOWN)
		if not await wait_for(func():return float(actor(GUEST).get("y",0.0))>float(tile.y)+1.65,"Tell the cutter to continue"):return
		session.input_direction(Vector2.ZERO)
		if await wait_for(func():return drop_amount()==0,"Pickup clears the other client's ground bundle"):
			expect(own_amount()==0,"The guest's backpack stays unchanged")

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2 or args[0] not in ["cutter","guest","server"]:
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
	print("BAMBOO_NETWORK role=%s checks=%d failures=%d"%[role,checks,failures])
	quit(int(failures>0))
