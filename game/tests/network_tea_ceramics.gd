extends SceneTree

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Tea=World.TEA_CERAMICS
const PREFIX:="tea-network-"
const ROOM:="tea-ceramics-test"
var session:Session
var receipts:Array[bool]=[]

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args[0]=="seed":
		var world:=World.new()
		world.save_path=args[1]
		world.state.chapter_one.shipped=true
		world.state.chapter_one.watered=true
		world.state.board=true
		world.state.picnic=true
		for role:String in ["alpha","beta"]:
			var token:=PREFIX+role
			world.add_player(token,role)
			world.state.players[token].x=44.5
			world.state.players[token].y=29.5
			var record:=Tea.FRESH.duplicate(true)
			record.intro=true
			world.state.tea_ceramics.players[token]=record
		var alpha:Dictionary=world.state.tea_ceramics.players[PREFIX+"alpha"]
		alpha.outbound={"style":"deep","wrap":"jar","reused_jar":false,"return_item":"tea_returned_jar","ready":0.0}
		alpha.harvest_ready={"0":5.0}
		quit(int(not world.save()))
		return
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	var alpha:=args[2]=="alpha"
	var initial:=args[0]=="start"
	session.profile.token=PREFIX+args[2]
	if session.join("127.0.0.1",int(args[1]),args[2],ROOM)!=OK:
		finish(false,"join request")
		return
	if not await until(func():return session.snapshot.get("players",{}).size()==2 and not session.own_id.is_empty(),5.0):
		finish(false,"two clients share the same region")
		return
	var data:Dictionary=session.snapshot
	var json:=JSON.stringify(data)
	var tea:Dictionary=data.get("tea_ceramics",{})
	if json.contains(PREFIX) or tea.size()!=1 or not tea.has("own_record"):
		finish(false,"raw actor token or foreign record exposed")
		return
	var own:Dictionary=tea.own_record
	if own.harvest_ready!=({"0":5.0} if alpha else {}) or (not own.outbound.is_empty())!=(alpha and initial):
		finish(false,"shipment or cooldown privacy")
		return
	session.notice.connect(func(_message:String,ok:bool):receipts.append(ok))
	var expected_success:=alpha and initial
	var sequence:=session.perform("tea_sell",Tea.RECEIVER)
	if not await until(func():return receipts.size()==1,3.0) or receipts[0]!=expected_success:
		finish(false,"sale permission")
		return
	var person:Dictionary=session.snapshot.players[session.own_id]
	session.request_action.rpc_id(1,sequence,"tea_sell",Tea.RECEIVER,"",session.snapshot.region_id,int(person.travel_epoch))
	await create_timer(0.35).timeout
	if receipts.size()!=1:
		finish(false,"duplicate RPC produced a receipt")
		return
	session.perform("tea_sell",Tea.RECEIVER)
	if not await until(func():return receipts.size()==2,3.0) or receipts[1]:
		finish(false,"new request cannot sell again")
		return
	if not await until(func():return settled(alpha),3.0):
		finish(false,"coins, empty jar and route state")
		return
	# Keep both clients connected long enough for the slower client to verify visibility.
	await create_timer(0.5).timeout
	finish(true,"%s %s"%[args[0],args[2]])

func settled(alpha:bool) -> bool:
	var state:Dictionary=session.snapshot
	var own:Dictionary=state.tea_ceramics.own_record
	var person:Dictionary=state.players[session.own_id]
	return int(person.coins)==120+(Tea.price_for("deep","jar") if alpha else 0) and int(own.empties)==int(alpha) and own.outbound.is_empty()

func until(predicate:Callable,seconds:float) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if predicate.call():return true
		await create_timer(0.05).timeout
	return false

func finish(ok:bool,step:String) -> void:
	if ok:print("TEA_CERAMICS_ENET_PASS ",step)
	else:push_error("TEA_CERAMICS_ENET_FAIL "+step)
	session.shutdown()
	quit(int(not ok))
