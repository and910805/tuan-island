extends SceneTree

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Table:=World.INDUSTRY
const Seat:=World.RESIDENT_GOALS.MASTER_BENCH_SEAT
const PLOT:=Vector2i(38,34)
const WOODEN:=Vector2i(39,34)
const VASE_TABLE:=Vector2i(40,34)
const SHARED_TABLE:=Vector2i(41,34)
const BOTTLE:="shell_bottle_tide"
const PASSWORD:="shell-table-test"
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
	return "shell-table-network-"+which

func seated(which:String,side:int)->bool:
	return actor(which).get(Seat,{})=={"cell":World.key(PLOT),"side":side}

func request(verb:String,item:String,expected:bool,tile:=PLOT)->bool:
	var target:=notices.size()
	session.perform(verb,tile,item)
	if not await wait_for(func():return notices.size()>target,"Receives an action result"):return false
	return expect(notices[target]==expected,"Action result matches the expected permissions")

func displayed()->bool:
	return session.snapshot.get("objects",{}).get(World.key(PLOT),{}).get("items",{})=={"flower_pot":1}

func bottle_displayed()->bool:
	return session.snapshot.get("objects",{}).get(World.key(WOODEN),{}).get("items",{})=={BOTTLE:1}

func bluebell_vase_displayed()->bool:
	return session.snapshot.get("objects",{}).get(World.key(VASE_TABLE),{}).get("items",{})=={"table_vase_bluebell":1}

func shared_items()->Dictionary:
	return session.snapshot.get("objects",{}).get(World.key(SHARED_TABLE),{}).get("items",{})

func serve(port:int)->void:
	var path:="user://shell-table-network-%d.json"%OS.get_process_id()
	if not expect(session.host(port,"貝殼圓桌連線驗收",path,PASSWORD,"127.0.0.1",true,"websocket")==OK,"Starts a dedicated WebSocket server"):return
	var world:World=session.world
	for which:String in ["alpha","beta"]:
		world.add_player(token(which),which,Vector2(38.5 if which=="alpha" else 39.5,33.5))
	var host:Dictionary=world.state.players[token("alpha")]
	host.inventory.wood=60
	host.inventory.seashell=4
	host.inventory[BOTTLE]=1
	host.inventory.flower_pot=1
	host.inventory[Table.TABLE_VASE]=1
	host.inventory.bluebell=1
	host.inventory.soup=1
	host.inventory.gold_sample=1
	world.state.players[token("beta")].mine_energy=40
	if not expect(world.act(token("alpha"),"setup-table","build",PLOT,Table.SHELL_TABLE).ok,"Builds the table using the normal construction rules"):return
	if not expect(world.act(token("alpha"),"setup-wooden","build",WOODEN,"table").ok,"Builds the wooden table"):return
	world.state.removed[World.key(VASE_TABLE)]=true
	if not expect(world.act(token("alpha"),"setup-vase-table","build",VASE_TABLE,"table").ok,"Builds a second wooden table for the vase"):return
	for tile:Vector2i in [SHARED_TABLE,SHARED_TABLE+Vector2i.RIGHT]:world.state.removed[World.key(tile)]=true
	if not expect(world.act(token("alpha"),"setup-shared-table","build",SHARED_TABLE,Table.ROUNDED_TABLE).ok,"Builds the two-cell round-corner table"):return
	if await wait_for(func():return session.peers.size()==2,"Two distinct clients connect",15.0):
		await wait_for(func():return session.peers.is_empty(),"Both clients finish and disconnect",24.0)
	expect(session.shutdown(),"The server closes and saves cleanly")
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func exercise(port:int)->void:
	session.profile.token=token(role)
	session.notice.connect(func(_message:String,success:bool):notices.append(success))
	if not expect(session.join("ws://127.0.0.1:%d"%port,port,role,PASSWORD)==OK,"Starts a WebSocket connection"):return
	if not await wait_for(func():return not actor("alpha").is_empty() and not actor("beta").is_empty(),"Both characters are visible"):return
	if role=="alpha":
		if not await request(Table.SHELL_PUT,"soup",true,SHARED_TABLE):return
		if not await request(Table.SHELL_PUT,"gold_sample",true,SHARED_TABLE):return
		if not await request(Table.SHELL_PUT,Table.TABLE_VASE,true,VASE_TABLE):return
		if not await request(Table.TABLE_VASE_SWAP,"bluebell",true,VASE_TABLE):return
		if not await wait_for(func():return bluebell_vase_displayed() and int(actor("alpha").get("inventory",{}).get("chime_herb",0))==1,"Owner receives one original flower"):return
		if not await request(Table.SHELL_PUT,BOTTLE,true,WOODEN):return
		if not await request(Table.SHELL_PUT,"flower_pot",true):return
		if not await request(Table.SHELL_SIT,"0",true):return
		if not await wait_for(func():return seated("beta",1) and seated("alpha",0) and displayed(),"Both seats and the displayed item agree on alpha's client"):return
		if not await wait_for(func():return shared_items()=={"gold_sample":1},"Owner sees only the meal removed after a guest eats"):return
		await create_timer(0.2).timeout
		if not await request(Table.SHELL_SIT,"0",true):return
		if not await wait_for(func():return actor("beta").is_empty(),"Beta can disconnect while using the right seat"):return
		if not await request(Table.SHELL_SIT,"1",true):return
		if not await wait_for(func():return seated("alpha",1),"The disconnected seat can be reused"):return
		if not await request(Table.SHELL_SIT,"1",true):return
		if not await request(Table.SHELL_TAKE,BOTTLE,true,WOODEN):return
		if not await wait_for(func():return not bottle_displayed() and int(actor("alpha").get("inventory",{}).get(BOTTLE,0))==1,"Owner retrieves the same bottle variant"):return
		if not await request(Table.SHELL_TAKE,"flower_pot",true):return
		await wait_for(func():return not displayed() and int(actor("alpha").get("inventory",{}).get("flower_pot",0))==1,"Owner retrieves exactly one display item")
	else:
		if not await wait_for(func():return seated("alpha",0) and displayed(),"Beta sees the occupied left seat and the displayed item"):return
		if not await wait_for(bottle_displayed,"Beta sees the exact shell bottle variant on the wooden table"):return
		if not await wait_for(bluebell_vase_displayed,"Beta sees the bluebell vase after the swap"):return
		if not await wait_for(func():return shared_items()=={"soup":1,"gold_sample":1},"Guest sees both occupied places"):return
		if not await request(Table.SHELL_TAKE,"gold_sample",false,SHARED_TABLE):return
		if not await request(Table.ROUNDED_EAT,"soup",true,SHARED_TABLE):return
		if not await wait_for(func():return shared_items()=={"gold_sample":1} and int(actor("beta").get("mine_energy",0))==52,"One portion is removed and the guest recovers stamina"):return
		if not await request(Table.ROUNDED_EAT,"soup",false,SHARED_TABLE):return
		if not await request(Table.TABLE_VASE_SWAP,"chime_herb",false,VASE_TABLE):return
		if not await request(Table.SHELL_TAKE,BOTTLE,false,WOODEN):return
		if not await request(Table.SHELL_TAKE,"flower_pot",false):return
		if not await request(Table.SHELL_SIT,"0",false):return
		if not await request(Table.SHELL_SIT,"1",true):return
		if not await wait_for(func():return seated("beta",1) and seated("alpha",0),"Beta sees both players seated at the same table"):return
		await wait_for(func():return not seated("alpha",0) and seated("beta",1),"Standing on the left leaves the right seat occupied")
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
	print("SHELL_TABLE_NETWORK_TESTS role=%s checks=%d failures=%d"%[role,checks,failures])
	quit(int(failures>0))
