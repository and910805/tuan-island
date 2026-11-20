extends SceneTree
## B5 石殼蟹 (stone-shelled crab) over a real WebSocket with distinct player identities:
## pre-unlock denial, the full life route, two-identity independence and privacy, the solid
## side cart, duplicate-delivery idempotency, three reconnects, a host restart on the same
## save file, old-save loading, unchanged base B5 actions, and the adventure soft-shell route.
##
## LEVEL (same harness as network_shy_mushroom.gd): one machine, ONE Godot process. A real
## dedicated server Session listens on a free 127.0.0.1 port with WebSocketMultiplayerPeer;
## each client Session joins over loopback from its own scene branch with its own
## SceneMultiplayer. Requests, notices, action results and snapshots really travel through
## RPC + WebSocket. Clients only read what they received. Not multi-process / multi-machine.
##
## FRAMES: "frame" means every signal a client Session emits for an inbound RPC. Every
## snapshot is checked on arrival for `stone_crab` under a foreign player entry and for raw
## profile tokens.
##
## CLOCK: the adventure windup (3.0 s) and window (2.5 s) run on the server's `state.time`.
## The test never touches it: it waits until the snapshot `time` a client received has passed
## the `open_at` the server replied with (plus a small margin).
##
## SEEDED FIXTURE "life" (disclosed): picnic=true; mine_depths={unlocked:5,pumped:24};
##   alpha  in mine_5 east cave (46.5,23.5), bag + plank 5, copper_joint 3
##   beta   same spot,                       bag + plank 2, copper_joint 1 (exactly the cost)
##   short  same spot,                       bag + plank 1 (cannot afford the repair)
##   miner  in mine_5 beside ore node (28,23), bag + reinforced_pick 1
##   No player carries a `stone_crab` field: this is also the "old save" of case 7.
## SEEDED FIXTURE "locked" (disclosed): picnic=true; mine_depths={unlocked:4,pumped:24}; one
##   player in mine_4 beside the DOWN ladder with plank 2 + copper_joint 1. A legal save
##   (SaveSchema rejects a player standing on a floor that is not open, asserted here).
## SEEDED FIXTURE "adventure" (disclosed): as "life" plus world_mode="adventure"; players
##   delta (plank 2, copper_joint 1) and echo in the cave.
## After the seed everything is done by clients: real movement input and Session.perform.
##
## NOT OVER THE SOCKET (labelled IN-PROCESS in the check text):
##  - SaveSchema accept / reject of hand-edited saves (case 1, 7).
##  - request-id receipt replay: over the socket a duplicate sequence is dropped by the
##    Session before World sees it (asserted: no reply, no spend). The receipt itself is
##    replayed by calling the live host's World.act with the very request id the host built.
##  - exact `unavailable` outcome for a player inside the B5 cave with B5 locked: no legal
##    save can hold that, so it is a direct World.act on a World that is never saved.
## SKIPPED: case 10 (rollback under a failed save). Neither network_shy_mushroom.gd nor
##   network_sleepy_stone_guardian.gd has a mechanism to fail the host's save; it is covered
##   at World level by the lead's test_stone_shelled_crab_world.gd.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Crab=preload("res://scripts/stone_shelled_crab.gd")
const Regions=preload("res://scripts/regions.gd")
const Mines=preload("res://scripts/mine_depths.gd")
const TAG:="STONE_SHELLED_CRAB_NETWORK"
const KEY:="stone-crab-net-key"
const ALPHA:="crab-net-alpha-token"
const BETA:="crab-net-beta-token"
const SHORT:="crab-net-short-token"
const MINER:="crab-net-miner-token"
const LOCKED:="crab-net-locked-token"
const DELTA:="crab-net-delta-token"
const ECHO:="crab-net-echo-token"
const TOKENS:=[ALPHA,BETA,SHORT,MINER,LOCKED,DELTA,ECHO]
const FIELD:="stone_crab"
## One spot within Crab.REACH of the cart (45,22), the crab (47,22) and its rest cell (46,22).
const STAND:=Vector2(46.5,23.5)
const BELOW_CART:=Vector2(45.5,23.5)
const ON_REST:=Vector2(46.5,22.5)
const ON_CRAB:=Vector2(47.5,22.5)
const SURVEY_POINT:=Vector2i(46,24)
const ORE_NODE:=Vector2i(28,23)
const MINER_STAND:=Vector2(28.5,21.5)
const MARGIN:=0.25
const REPLY_FIELDS:=["outcome","stage","claimed","cues","missing","open_at","close_at"]

class Client:
	var label:=""
	var token:=""
	var branch:Node
	var session
	## One entry per signal emitted by the client Session. Snapshots keep no payload.
	var frames:Array=[]
	var changes:=0
	var needles:Array=[]
	var snapshot_hits:Array=[]
	func tap() -> void:
		for info in session.get_script().get_script_signal_list():
			var signal_name:String=info.name
			session.connect(signal_name,func(a=null,b=null,c=null,d=null,e=null):on_frame(signal_name,[a,b,c,d,e]))
	func on_frame(signal_name:String,args:Array) -> void:
		if signal_name=="changed":
			changes+=1
			var snap=args[0]
			var own:=str(args[1])
			if snap is Dictionary:
				var people=snap.get("players",{})
				if people is Dictionary:
					for id in people:
						if str(id)!=own and people[id] is Dictionary and people[id].has("stone_crab"):
							snapshot_hits.append("snapshot #%d exposes stone_crab under foreign player %s"%[changes,str(id)])
				var text:=JSON.stringify(snap)
				for needle:String in needles:
					if text.contains(needle):snapshot_hits.append("snapshot #%d contains %s"%[changes,needle])
			frames.append({"name":signal_name,"args":[]})
		else:
			frames.append({"name":signal_name,"args":args})
	func others(mark:int) -> Array:
		var out:Array=[]
		for i in range(mark,frames.size()):
			if frames[i].name!="changed":out.append(frames[i])
		return out
	func notices(mark:int) -> Array:
		return others(mark).filter(func(f):return f.name=="notice")
	func completions(mark:int) -> Array:
		return others(mark).filter(func(f):return f.name=="action_completed")
	## Every `crab` payload received since `mark` (any signal, any argument).
	func payloads(mark:int) -> Array:
		var out:Array=[]
		for frame in others(mark):
			for arg in frame.args:
				if arg is Dictionary and arg.get("crab") is Dictionary:out.append(arg.crab)
		return out
	func me()->Dictionary:
		var people=session.snapshot.get("players",{})
		if not people is Dictionary or session.own_id.is_empty():return {}
		return people.get(session.own_id,{})
	func region()->String:
		return str(session.snapshot.get("region_id",""))
	func pos()->Vector2:
		var p:=me()
		return Vector2(float(p.get("x",-99.0)),float(p.get("y",-99.0)))
	func cell()->Vector2i:
		var at:=pos()
		return Vector2i(floori(at.x),floori(at.y))
	func inventory()->Dictionary:
		var inv=me().get("inventory",{})
		return (inv as Dictionary).duplicate(true) if inv is Dictionary else {}
	func count(item:String)->int:
		return int(inventory().get(item,0))
	func wtime()->float:
		var value=session.snapshot.get("time")
		return float(value) if (value is float or value is int) else -1.0
	## The client's own record as its snapshot exposes it (null if absent).
	func own_view():
		var mine=me().get("stone_crab")
		return mine if mine is Dictionary else null
	func seen_pages()->Dictionary:
		var block=session.snapshot.get("mine_survey",{})
		if not block is Dictionary:return {}
		var record=block.get("own_record",{})
		return record.get("seen",{}) if record is Dictionary else {}

var checks:=0
var failures:=0
var serial:=0
var folders:Array=[]
var save_path:=""
var server
var server_branch:Node
var finished:=false
var replies:=0
var crab_replies_expected:=0
var crab_replies_with_payload:=0
var live:Array=[]

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+message)
		print("FAIL "+message)

func _initialize()->void:
	create_timer(270.0).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	push_error("%s watchdog fired before completion"%TAG)
	print("%s watchdog fired before completion"%TAG)
	print("STONE_SHELLED_CRAB_NETWORK_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion (an early stop means a required step did not happen)")
	await teardown()
	expect(remove_folders(),"isolated temp save folders removed")
	if finished:return
	finished=true
	print("%s replies=%d crab_replies_expected=%d crab_replies_with_payload=%d duration_ms=%d"%[TAG,replies,crab_replies_expected,crab_replies_with_payload,Time.get_ticks_msec()-started])
	print("%s SKIPPED case 10 (failed-save rollback): no network-level save-failure mechanism in the shy / guardian harness; World-level test covers it"%TAG)
	if failures==0 and checks==0:failures=1
	print("STONE_SHELLED_CRAB_NETWORK_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

# ---------------------------------------------------------------- fixture --

func validate(data)->bool:
	return data is Dictionary and Schema.validate(data,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func read_save():
	return JSON.parse_string(FileAccess.get_file_as_string(save_path))

## placements: token -> [region, preferred standing position, extra inventory]
func seed_fixture(name:String,unlocked:int,adventure:bool,placements:Dictionary)->bool:
	var folder:=OS.get_environment("TEMP").path_join("stone-crab-net-%s-%s"%[name,Crypto.new().generate_random_bytes(8).hex_encode()])
	if DirAccess.make_dir_recursive_absolute(folder)!=OK:return false
	folders.append(folder)
	save_path=folder.path_join("stone_crab_world.json")
	var w:=World.new()
	w.save_path=save_path
	w.state["picnic"]=true
	w.state["mine_depths"]={"unlocked":unlocked,"ready":{},"pumped":24 if unlocked>=3 else 0,"hoist":false}
	if adventure:w.state["world_mode"]="adventure"
	for token:String in placements:
		var where:Array=placements[token]
		w.switch_region(str(where[0]))
		var spot:=w.safe_arrival(where[1])
		w.switch_region(Regions.HOME)
		if spot==Vector2.ZERO:return false
		w.add_player(token,token.get_slice("-",2))
		var p:Dictionary=w.state.players[token]
		p["region"]=str(where[0])
		p["x"]=spot.x
		p["y"]=spot.y
		var extra:Dictionary=where[2]
		for item:String in extra:p.inventory[item]=int(extra[item])
	w.active_tokens.clear()
	if not w.save():return false
	return validate(read_save())

# ------------------------------------------------------------- transport --

func new_branch(prefix:String)->Node:
	serial+=1
	var branch:=Node.new()
	branch.name="%s%d"%[prefix,serial]
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(),branch.get_path())
	return branch

func start_server()->int:
	server_branch=new_branch("Server")
	server=Session.new()
	server_branch.add_child(server)
	for attempt in 8:
		# network_shy_mushroom / network_sleepy_stone_guardian draw from 31000-58000 and the
		# fixed-port clients use 28551 / 28711: this range is used by no other network test.
		var port:=randi_range(58101,59990)
		if server.host(port,"",save_path,KEY,"127.0.0.1",true,"websocket")==OK:return port
	return 0

func stop_server()->bool:
	var saved:bool=server.shutdown()
	await pause(0.2)
	server_branch.queue_free()
	await process_frame
	return saved

func join(label:String,token:String,port:int)->Client:
	var c:=Client.new()
	c.label=label
	c.token=token
	c.needles=TOKENS.duplicate()
	c.branch=new_branch("Client_%s_"%label)
	c.session=Session.new()
	c.branch.add_child(c.session)
	c.session.profile["token"]=token
	c.tap()
	live.append(c)
	if c.session.join("ws://127.0.0.1:%d"%port,port,label,KEY)!=OK:return c
	await wait_until(func():return not c.session.own_id.is_empty() and not c.me().is_empty(),8.0)
	return c

func joined(c:Client)->bool:
	return c!=null and is_instance_valid(c.session) and not c.session.own_id.is_empty() and not c.me().is_empty()

func leave(c:Client)->void:
	if c==null or not is_instance_valid(c.session):return
	if not c.session.shutting_down:c.session.shutdown()
	await process_frame
	c.branch.queue_free()
	# Harness sync only: do not rejoin before the host has dropped this identity.
	await wait_until(func():return server==null or not is_instance_valid(server) or not (c.token in server.peers.values()),4.0)

func rejoin(c:Client,port:int)->Client:
	await leave(c)
	var again:=await join(c.label,c.token,port)
	if joined(again):await settle([again])
	return again

func wait_until(condition:Callable,seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await process_frame
	return condition.call()

func pause(seconds:float)->void:
	await create_timer(seconds).timeout

func settle(clients:Array)->void:
	var marks:Array=clients.map(func(c):return c.changes)
	await wait_until(func():
		for i in clients.size():
			if clients[i].changes<int(marks[i])+2:return false
		return true,3.0)

## Sends one action and collects what THIS client received for it: the notice and any
## action_completed frame (with its `crab` payload when present). Bounded: 4 s for a reply.
func act(c:Client,action:String,target:Vector2i,extra:String="",want_crab:bool=true)->Dictionary:
	var mark:=c.frames.size()
	var sequence:int=c.session.perform(action,target,extra)
	if want_crab:crab_replies_expected+=1
	var replied:=await wait_until(func():return not c.notices(mark).is_empty() or not c.completions(mark).is_empty(),4.0)
	if not replied:return {"replied":false,"ok":false,"message":"","crab":{},"done":0,"matched":false,"result_ok":false,"notices":0,"sequence":sequence,"result":{}}
	await wait_until(func():return not c.notices(mark).is_empty() and not c.completions(mark).is_empty(),0.7)
	await settle([c])
	var notes:Array=c.notices(mark)
	var done:Array=c.completions(mark)
	var crab:Dictionary={}
	var full:Dictionary={}
	var matched:=false
	var result_ok:=false
	if not done.is_empty():
		var result=done[0].args[2]
		matched=int(done[0].args[0])==sequence and str(done[0].args[1])==action
		if result is Dictionary:
			full=result
			result_ok=bool(result.get("ok",false))
			if result.get("crab") is Dictionary:crab=result.crab
	replies+=1
	if want_crab and not crab.is_empty():crab_replies_with_payload+=1
	var message:String=str(notes[0].args[0]) if not notes.is_empty() else str(full.get("message",""))
	var ok_value:bool=bool(notes[0].args[1]) if not notes.is_empty() else result_ok
	return {"replied":true,"ok":ok_value,"message":message,"crab":crab,"done":done.size(),"matched":matched,"result_ok":result_ok,"notices":notes.size(),"sequence":sequence,"result":full}

func brief(reply:Dictionary)->String:
	return "{replied=%s ok=%s msg=%s completed=%s crab=%s}"%[str(reply.replied),str(reply.ok),str(reply.message).left(20),str(reply.done),str(reply.crab)]

func outcome(reply:Dictionary)->String:
	return str(reply.crab.get("outcome","<no crab payload>"))

## A crab reply: a notice plus exactly one correlated action_completed whose result.crab has
## every contract field and the wanted outcome / stage / claimed / cues.
func crab_is(reply:Dictionary,want_ok:bool,want_outcome:String,want_stage:int,want_claimed:bool,want_cues:Array)->bool:
	if not reply.replied or reply.ok!=want_ok or reply.done!=1 or not reply.matched or reply.result_ok!=want_ok:return false
	if str(reply.message).is_empty():return false
	var crab:Dictionary=reply.crab
	for field in REPLY_FIELDS:
		if not crab.has(field):return false
	if not crab.cues is Array or not crab.claimed is bool or not crab.missing is Dictionary:return false
	return str(crab.outcome)==want_outcome and int(crab.stage)==want_stage and crab.claimed==want_claimed and Array(crab.cues)==want_cues

func no_cycle(reply:Dictionary)->bool:
	return float(reply.crab.get("open_at",0.0))==-1.0 and float(reply.crab.get("close_at",0.0))==-1.0

func ints(source)->Dictionary:
	var out:Dictionary={}
	if source is Dictionary:
		for item in source:out[str(item)]=int(source[item])
	return out

## Item count changes between two inventories (zero changes left out).
func change(before:Dictionary,after:Dictionary)->Dictionary:
	var out:Dictionary={}
	for item in before:
		var moved:=int(after.get(item,0))-int(before[item])
		if moved!=0:out[str(item)]=moved
	for item in after:
		if not before.has(item) and int(after[item])!=0:out[str(item)]=int(after[item])
	return out

## Own snapshot record. `absent` demands that the field does not exist at all.
func view_is(c:Client,want_stage:int,want_claimed:bool)->bool:
	var view=c.own_view()
	if view==null:return want_stage==0 and not want_claimed
	return Crab.valid(view) and int(view.stage)==want_stage and view.claimed==want_claimed

func walk(c:Client,points:Array,seconds:float=10.0)->bool:
	var index:=0
	var deadline:=Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<deadline and index<points.size():
		var last:bool=index==points.size()-1
		var offset:Vector2=points[index]-c.pos()
		if offset.length()<(0.2 if last else 0.4):
			index+=1
			continue
		c.session.input_direction(offset.limit_length() if last else offset.normalized())
		await create_timer(0.05).timeout
	c.session.input_direction(Vector2.ZERO)
	await pause(0.3)
	await settle([c])
	return index>=points.size()

func go(c:Client,target:Vector2)->bool:
	if c.pos().distance_to(target)<0.2:return true
	return await walk(c,[target])

## Holds a movement direction for a fixed real time (walking into something).
func push(c:Client,direction:Vector2,seconds:float)->void:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<deadline:
		c.session.input_direction(direction)
		await create_timer(0.05).timeout
	c.session.input_direction(Vector2.ZERO)
	await pause(0.3)
	await settle([c])

## Waits (real time, bounded) until the snapshots this client receives show the server clock
## at or past `target`.
func wait_world(c:Client,target:float)->bool:
	if c.wtime()<0.0:
		await pause(Crab.SHELL_WINDUP+0.6)
		return false
	return await wait_until(func():return c.wtime()>=target,20.0)

func foreign_crab(viewer:Client,subject:Client)->bool:
	var entry=viewer.session.snapshot.get("players",{}).get(subject.session.own_id,{})
	return entry is Dictionary and entry.has(FIELD)

## Frames `watcher` received since `mark` that belong to someone else's crab play.
func quiet_for(watcher:Client,mark:int,actor_messages:Array)->bool:
	var clean:=watcher.completions(mark).is_empty() and watcher.payloads(mark).is_empty()
	for note in watcher.notices(mark):
		if str(note.args[0]) in actor_messages:clean=false
	if not clean:
		for frame in watcher.others(mark):print("  frame to %s: %s %s"%[watcher.label,frame.name,str(frame.args).left(200)])
	return clean

## Re-delivers the SAME sequence number the client just used (duplicate transport delivery,
## the mechanism network_shy_mushroom.gd uses). Returns true if nothing came back.
func resend_same_sequence(c:Client,action:String,target:Vector2i)->bool:
	var mark:=c.frames.size()
	c.session.request_action.rpc_id(1,c.session.counter,action,target,"",c.region(),int(c.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([c])
	return c.others(mark).is_empty()

## IN-PROCESS: asks the live host World for the same request id the host built for `reply`
## ("<session nonce>-<peer id>-<sequence>"). A stored receipt must come back unchanged.
func receipt_replay(c:Client,reply:Dictionary,action:String,target:Vector2i):
	var nonce=server.get("session_nonce")
	if nonce==null or str(nonce).is_empty():return null
	var request_id:="%s-%d-%d"%[str(nonce),c.session.multiplayer.get_unique_id(),int(reply.sequence)]
	if not (server.world.state.players[c.token].receipts as Dictionary).has(request_id):return null
	return server.world.act(c.token,request_id,action,target,"")

func same_answer(replayed,reply:Dictionary)->bool:
	if not replayed is Dictionary or not replayed.get("crab") is Dictionary:return false
	var a:Dictionary=replayed.crab
	var b:Dictionary=reply.crab
	return bool(replayed.get("ok",false))==bool(reply.result_ok) and str(replayed.get("message",""))==str(reply.message) \
		and str(a.get("outcome",""))==str(b.get("outcome","?")) and int(a.get("stage",-1))==int(b.get("stage",-2)) \
		and a.get("claimed")==b.get("claimed") and Array(a.get("cues",[]))==Array(b.get("cues",["?"])) and ints(a.get("missing",{}))==ints(b.get("missing",{}))

func saved_record_is(person:Dictionary,want_stage:int,want_claimed:bool)->bool:
	var saved=person.get(FIELD)
	return saved is Dictionary and Crab.valid(saved) and int(saved.stage)==want_stage and saved.claimed==want_claimed

func saved_count(person:Dictionary,item:String)->int:
	return int((person.get("inventory",{}) as Dictionary).get(item,0))

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	if not await phase_locked():return false
	if not await phase_life():return false
	if not await phase_adventure():return false
	direct_gate()
	return true

# ---- case 1: B5 not open yet (fixture "locked", its own host) ---------------
func phase_locked()->bool:
	var ladder:=Vector2(Mines.DOWN)+Vector2(-0.5,0.5)
	expect(seed_fixture("locked",4,false,{LOCKED:["mine_4",ladder,{"plank":2,"copper_joint":1}]}),"case1 SEEDED fixture 'locked' (unlocked=4, player in mine_4 beside the DOWN ladder) written and accepted by SaveSchema")
	if save_path.is_empty() or not FileAccess.file_exists(save_path):return false
	# IN-PROCESS SaveSchema checks on this very save.
	var with_record=read_save()
	var has_player:bool=with_record is Dictionary and with_record.get("players",{}).has(LOCKED)
	expect(has_player and not (with_record.players[LOCKED] as Dictionary).has(FIELD),"case1 fixture 'locked' carries no stone_crab field")
	if not has_player:return false
	for record in [{"stage":0,"claimed":false},{"stage":1,"claimed":false},{"stage":2,"claimed":true}]:
		var edited:Dictionary=(with_record as Dictionary).duplicate(true)
		edited.players[LOCKED][FIELD]=record
		expect(not validate(edited),"case1 IN-PROCESS SaveSchema rejects stone_crab %s while mine_depths.unlocked=4"%str(record))
	var moved:Dictionary=(with_record as Dictionary).duplicate(true)
	moved.players[LOCKED]["region"]=Crab.REGION
	moved.players[LOCKED]["x"]=STAND.x
	moved.players[LOCKED]["y"]=STAND.y
	expect(not validate(moved),"case1 IN-PROCESS SaveSchema rejects the same save once the player stands in mine_5 while unlocked=4 (why the fixture keeps the player in mine_4)")
	var port:=start_server()
	expect(port>0,"case1 host serves fixture 'locked' on 127.0.0.1 over websocket")
	if port==0:return false
	var locked:=await join("locked",LOCKED,port)
	expect(joined(locked),"case1 locked client joined over loopback")
	if not joined(locked):return false
	await settle([locked])
	var ws:bool=server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and locked.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer
	expect(ws and server.multiplayer.is_server() and not locked.session.multiplayer.is_server() and locked.session.world==null,"real WebSocket server + remote client (client holds no World)")
	print("%s_LABEL machine=single process=single transport=%s loopback=127.0.0.1:%d fixtures=SEEDED(position,bag,mine progress,picnic,world_mode) clock=real(server state.time read from snapshots)"%[TAG,"websocket" if ws else "UNEXPECTED",port])
	var start_pos:=locked.pos()
	var bag:=locked.inventory()
	var epoch:=int(locked.me().get("travel_epoch",0))
	expect(locked.region()=="mine_4" and locked.count("plank")==2 and locked.count("copper_joint")==1 and locked.own_view()==null,"case1 locked client is in mine_4 holding the repair materials, no stone_crab field (region %s)"%locked.region())
	# mine_travel DOWN to mine_5 is refused.
	var mark:=locked.frames.size()
	locked.session.perform("mine_travel",Mines.DOWN,Crab.REGION)
	expect(await wait_until(func():return not locked.notices(mark).is_empty(),4.0),"case1 mine_travel to mine_5 is answered with a notice")
	await settle([locked])
	var notes:Array=locked.notices(mark)
	expect(not notes.is_empty() and not bool(notes[0].args[1]) and locked.completions(mark).is_empty(),"case1 mine_travel DOWN to mine_5 with unlocked=4 is refused (got %s)"%str(notes.map(func(f):return f.args.slice(0,2))))
	expect(locked.region()=="mine_4" and int(locked.me().get("travel_epoch",0))==epoch and locked.pos().distance_to(start_pos)<0.05,"case1 still in mine_4 at the same spot and travel epoch (region %s pos %s)"%[locked.region(),str(locked.pos())])
	# Every crab action is refused. mine_4 has no floor within the ordinary reach of the B5
	# cave cells, so the host's generic reach guard may answer first (no crab payload).
	var attempts:=[["crab_survey",Crab.CRAB,""],["crab_repair",Crab.CART,""],["crab_claim",Crab.CRAB,""],["crab_claim",Crab.CRAB_REST,""],["crab_shell",Crab.CRAB,"wait"],["crab_shell",Crab.CRAB,"tap"]]
	for attempt:Array in attempts:
		var refused:=await act(locked,attempt[0],attempt[1],attempt[2],false)
		expect(refused.replied and not refused.ok and not refused.result_ok and (refused.crab.is_empty() or outcome(refused) in ["unavailable","life_mode","invalid","far"]),"case1 %s %s from a world with B5 locked is refused (got %s)"%[attempt[0],attempt[2],brief(refused)])
		expect(refused.crab.is_empty() or (int(refused.crab.get("stage",-1))==0 and refused.crab.get("claimed")==false),"case1 refused %s reports no progress (got %s)"%[attempt[0],str(refused.crab)])
		print("%s INFO locked %s%s -> outcome=%s msg=%s"%[TAG,attempt[0]," "+str(attempt[2]) if attempt[2]!="" else "",outcome(refused),refused.message])
	await settle([locked])
	expect(locked.own_view()==null and locked.inventory()==bag,"case1 no stone_crab field and bag unchanged after the refused actions (view %s, change %s)"%[str(locked.own_view()),str(change(bag,locked.inventory()))])
	expect(locked.snapshot_hits.is_empty(),"case1 no snapshot carried raw tokens %s"%str(locked.snapshot_hits.slice(0,3)))
	await leave(locked)
	expect(await stop_server(),"case1 host shuts down with a final save")
	var disk=read_save()
	var untouched:bool=disk is Dictionary and validate((disk as Dictionary).duplicate(true))
	if untouched:
		var person:Dictionary=disk.players.get(LOCKED,{})
		untouched=str(person.get("region",""))=="mine_4" and not person.has(FIELD) and int(disk.mine_depths.unlocked)==4 and saved_count(person,"plank")==2 and saved_count(person,"copper_joint")==1 and saved_count(person,"gold_ore")==0
	expect(untouched,"case1 save after play: valid, player still in mine_4, unlocked=4, no stone_crab, materials untouched, no gold_ore")
	return true

# ---- cases 2-8: life world ---------------------------------------------------
func phase_life()->bool:
	var cave:=Crab.REGION
	expect(seed_fixture("life",5,false,{
		ALPHA:[cave,STAND,{"plank":5,"copper_joint":3}],
		BETA:[cave,STAND,{"plank":2,"copper_joint":1}],
		SHORT:[cave,STAND,{"plank":1}],
		MINER:[cave,MINER_STAND,{"reinforced_pick":1}]}),"SEEDED fixture 'life' (picnic, unlocked=5, four players placed in mine_5) written and accepted by SaveSchema")
	if save_path.is_empty() or not FileAccess.file_exists(save_path):return false
	# case 7 (old save): no player carries the field. IN-PROCESS schema controls on a copy.
	var old=read_save()
	var old_ok:bool=old is Dictionary and not old.has("world_mode")
	if old_ok:
		for token:String in [ALPHA,BETA,SHORT,MINER]:
			if not old.players.has(token) or (old.players[token] as Dictionary).has(FIELD):old_ok=false
	expect(old_ok,"case7 fixture 'life' is an old-style save: no player has a stone_crab field, no world_mode")
	if not old_ok:return false
	var legal:Dictionary=(old as Dictionary).duplicate(true)
	legal.players[ALPHA][FIELD]={"stage":1,"claimed":false}
	expect(validate(legal),"case1 control IN-PROCESS: the same record is accepted once unlocked=5 (the rejection above is the B5 gate)")
	for bad in [{"stage":1,"claimed":true},{"stage":3,"claimed":false},{"stage":1,"claimed":false,"extra":1},{"stage":1.5,"claimed":false}]:
		var broken:Dictionary=(old as Dictionary).duplicate(true)
		broken.players[ALPHA][FIELD]=bad
		expect(not validate(broken),"case7 IN-PROCESS SaveSchema rejects malformed stone_crab %s"%str(bad))
	var port:=start_server()
	expect(port>0,"host serves fixture 'life' on 127.0.0.1 over websocket")
	if port==0:return false
	var alpha:=await join("alpha",ALPHA,port)
	var beta:=await join("beta",BETA,port)
	expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback")
	if not joined(alpha) or not joined(beta):return false
	await settle([alpha,beta])
	expect(alpha.session.own_id!=beta.session.own_id and alpha.session.own_id!=ALPHA and beta.session.own_id!=BETA,"two distinct public ids, neither equal to a profile token")
	expect(alpha.region()==cave and beta.region()==cave and Crab.near(alpha.pos(),Crab.CART) and Crab.near(alpha.pos(),Crab.CRAB) and Crab.near(alpha.pos(),Crab.CRAB_REST),"both stand in the B5 east cave within reach of cart, crab and rest cell (alpha %s)"%str(alpha.pos()))
	expect(alpha.wtime()>=0.0,"snapshots carry the server clock `time`")
	# case 7: both start fresh from the old save.
	expect(alpha.own_view()==null and beta.own_view()==null,"case7 old save loads and both identities start with no stone_crab field (%s / %s)"%[str(alpha.own_view()),str(beta.own_view())])
	var a0:=alpha.inventory()
	var b0:=beta.inventory()
	expect(alpha.count("plank")==5 and alpha.count("copper_joint")==3 and beta.count("plank")==2 and beta.count("copper_joint")==1 and alpha.count("gold_ore")==0 and beta.count("gold_ore")==0,"seeded bags arrived: alpha plank 5 / joint 3, beta plank 2 / joint 1, no gold_ore")
	var beta_mark:=beta.frames.size()
	var beta_changes:=beta.changes
	var alpha_messages:Array=[]

	# ---- case 2: alpha's life route -----------------------------------------
	var early_repair:=await act(alpha,"crab_repair",Crab.CART)
	alpha_messages.append(early_repair.message)
	expect(crab_is(early_repair,false,"too_early",0,false,[]) and no_cycle(early_repair),"case2 repair BEFORE survey is too_early (got %s)"%brief(early_repair))
	expect(alpha.inventory()==a0 and alpha.own_view()==null,"case2 too_early repair spent nothing and wrote no record (change %s, view %s)"%[str(change(a0,alpha.inventory())),str(alpha.own_view())])
	var early_claim:=await act(alpha,"crab_claim",Crab.CRAB)
	alpha_messages.append(early_claim.message)
	expect(crab_is(early_claim,false,"waiting",0,false,[]) and alpha.inventory()==a0,"case2 claim before anything is refused as waiting, bag unchanged (got %s)"%brief(early_claim))
	var bad_extra:=await act(alpha,"crab_survey",Crab.CRAB,"x")
	alpha_messages.append(bad_extra.message)
	expect(crab_is(bad_extra,false,"invalid",0,false,[]),"case2 crab_survey with a stray extra is invalid (got %s)"%brief(bad_extra))
	var wrong_cell:=await act(alpha,"crab_survey",Crab.CRAB_REST)
	alpha_messages.append(wrong_cell.message)
	expect(crab_is(wrong_cell,false,"far",0,false,[]) and alpha.own_view()==null,"case2 crab_survey aimed at the rest cell while the crab is still at (47,22) is far (got %s)"%brief(wrong_cell))
	var look:=await act(alpha,"crab_survey",Crab.CRAB)
	alpha_messages.append(look.message)
	expect(crab_is(look,true,"look",1,false,["crab_clack"]) and no_cycle(look),"case2 first crab_survey is look, stage 1, cue crab_clack (got %s)"%brief(look))
	expect(view_is(alpha,1,false) and alpha.own_view()!=null and alpha.inventory()==a0,"case2 own snapshot now shows {stage 1, unclaimed}; survey is free (view %s)"%str(alpha.own_view()))
	if outcome(look)!="look":return false
	var again:=await act(alpha,"crab_survey",Crab.CRAB)
	alpha_messages.append(again.message)
	expect(crab_is(again,true,"alert",1,false,["crab_clack"]) and view_is(alpha,1,false),"case2 second crab_survey is alert, still stage 1 (got %s)"%brief(again))
	var life_shell:=await act(alpha,"crab_shell",Crab.CRAB,"wait")
	alpha_messages.append(life_shell.message)
	expect(crab_is(life_shell,false,"life_mode",1,false,[]) and no_cycle(life_shell),"case9 (life world) crab_shell wait is refused with life_mode (got %s)"%brief(life_shell))
	var life_tap:=await act(alpha,"crab_shell",Crab.CRAB,"tap")
	alpha_messages.append(life_tap.message)
	expect(crab_is(life_tap,false,"life_mode",1,false,[]) and view_is(alpha,1,false) and alpha.inventory()==a0,"case9 (life world) crab_shell tap is refused with life_mode, nothing changes (got %s)"%brief(life_tap))

	# ---- case 5a: reconnect at stage 1 ---------------------------------------
	alpha=await rejoin(alpha,port)
	expect(joined(alpha),"case5 alpha reconnects at stage 1 with the same token")
	if not joined(alpha):return false
	expect(view_is(alpha,1,false) and alpha.own_view()!=null and alpha.inventory()==a0,"case5 reconnected alpha: stage 1 kept, bag identical (view %s, change %s)"%[str(alpha.own_view()),str(change(a0,alpha.inventory()))])

	# ---- case 2: short of materials (identity `short`) -----------------------
	var short:=await join("short",SHORT,port)
	expect(joined(short),"short joined")
	if not joined(short):return false
	await settle([short])
	var s0:=short.inventory()
	expect(short.count("plank")==1 and short.count("copper_joint")==0 and short.own_view()==null,"case2 short starts with plank 1, no copper_joint, no record")
	var s_look:=await act(short,"crab_survey",Crab.CRAB)
	expect(crab_is(s_look,true,"look",1,false,["crab_clack"]),"case2 short: survey is look (got %s)"%brief(s_look))
	var s_repair:=await act(short,"crab_repair",Crab.CART)
	expect(crab_is(s_repair,false,"short",1,false,[]),"case2 short: repair without materials is short (got %s)"%brief(s_repair))
	expect(ints(s_repair.crab.get("missing",{}))=={"plank":1,"copper_joint":1},"case2 short: missing map is {plank 1, copper_joint 1} (got %s)"%str(s_repair.crab.get("missing")))
	expect(short.inventory()==s0 and view_is(short,1,false),"case2 short: nothing spent, still stage 1 (change %s, view %s)"%[str(change(s0,short.inventory())),str(short.own_view())])
	var s_claim:=await act(short,"crab_claim",Crab.CRAB)
	expect(crab_is(s_claim,false,"waiting",1,false,[]) and short.count("gold_ore")==0,"case2 short: claim at stage 1 is waiting, no gold_ore (got %s)"%brief(s_claim))
	expect(not foreign_crab(short,alpha) and not foreign_crab(alpha,short),"case3 short and alpha do not see each other's stone_crab")
	await leave(short)

	# ---- case 2 + 4: alpha repairs; duplicate delivery ------------------------
	var repair:=await act(alpha,"crab_repair",Crab.CART)
	alpha_messages.append(repair.message)
	expect(crab_is(repair,true,"repair",2,false,["crab_hammer","crab_wheel","crab_scuttle"]) and ints(repair.crab.get("missing",{})).is_empty(),"case2 repair after survey succeeds, stage 2, three cues (got %s)"%brief(repair))
	if outcome(repair)!="repair":return false
	var a1:=alpha.inventory()
	expect(change(a0,a1)=={"plank":-2,"copper_joint":-1},"case2 repair spent exactly plank 2 + copper_joint 1 and nothing else (change %s)"%str(change(a0,a1)))
	expect(view_is(alpha,2,false) and alpha.count("gold_ore")==0,"case2 own snapshot {stage 2, unclaimed}, no gold_ore yet (view %s)"%str(alpha.own_view()))
	expect(await resend_same_sequence(alpha,"crab_repair",Crab.CART),"case4 the same repair sequence delivered twice gets no second reply over the socket")
	expect(alpha.inventory()==a1 and view_is(alpha,2,false),"case4 duplicate repair delivery: no second spend (change %s)"%str(change(a1,alpha.inventory())))
	var repair_replay=receipt_replay(alpha,repair,"crab_repair",Crab.CART)
	expect(same_answer(repair_replay,repair),"case4 IN-PROCESS same request id replays the stored repair result unchanged (got %s)"%str(repair_replay))
	await settle([alpha])
	expect(alpha.inventory()==a1 and saved_count(server.world.state.players[ALPHA],"plank")==3 and saved_count(server.world.state.players[ALPHA],"copper_joint")==2,"case4 receipt replay spent nothing: host still holds plank 3 / copper_joint 2")
	var settled_repair:=await act(alpha,"crab_repair",Crab.CART)
	alpha_messages.append(settled_repair.message)
	expect(crab_is(settled_repair,false,"settled",2,false,[]) and alpha.inventory()==a1,"case2 a fresh repair request on the mended cart is settled and spends nothing (got %s)"%brief(settled_repair))
	var stale_cell:=await act(alpha,"crab_claim",Crab.CRAB)
	alpha_messages.append(stale_cell.message)
	expect(crab_is(stale_cell,false,"far",2,false,[]) and alpha.count("gold_ore")==0,"case2 claim aimed at the old crab cell (47,22) after it moved is far (got %s)"%brief(stale_cell))

	# ---- case 5b: reconnect at stage 2, unclaimed -----------------------------
	alpha=await rejoin(alpha,port)
	expect(joined(alpha),"case5 alpha reconnects at stage 2 unclaimed")
	if not joined(alpha):return false
	expect(view_is(alpha,2,false) and alpha.inventory()==a1 and alpha.count("gold_ore")==0,"case5 reconnected alpha: stage 2 unclaimed kept, bag identical, no reward on reconnect (view %s, change %s)"%[str(alpha.own_view()),str(change(a1,alpha.inventory()))])

	# ---- case 2 + 4: claim; duplicate delivery --------------------------------
	var claim:=await act(alpha,"crab_claim",Crab.CRAB_REST)
	alpha_messages.append(claim.message)
	expect(crab_is(claim,true,"claim",2,true,["crab_chime"]),"case2 crab_claim at the rest cell succeeds (got %s)"%brief(claim))
	if outcome(claim)!="claim":return false
	var a2:=alpha.inventory()
	expect(change(a1,a2)=={Crab.REWARD_ITEM:Crab.REWARD_COUNT} and view_is(alpha,2,true),"case2 claim gave exactly gold_ore +2 and set claimed (change %s, view %s)"%[str(change(a1,a2)),str(alpha.own_view())])
	expect(await resend_same_sequence(alpha,"crab_claim",Crab.CRAB_REST),"case4 the same claim sequence delivered twice gets no second reply over the socket")
	expect(alpha.inventory()==a2,"case4 duplicate claim delivery: no second reward (change %s)"%str(change(a2,alpha.inventory())))
	var claim_replay=receipt_replay(alpha,claim,"crab_claim",Crab.CRAB_REST)
	expect(same_answer(claim_replay,claim),"case4 IN-PROCESS same request id replays the stored claim result unchanged (got %s)"%str(claim_replay))
	await settle([alpha])
	expect(alpha.inventory()==a2 and saved_count(server.world.state.players[ALPHA],"gold_ore")==Crab.REWARD_COUNT,"case4 receipt replay granted nothing: host still holds gold_ore 2")
	var twice:=await act(alpha,"crab_claim",Crab.CRAB_REST)
	alpha_messages.append(twice.message)
	expect(crab_is(twice,false,"claimed",2,true,[]) and alpha.inventory()==a2,"case2 second claim is refused as claimed, bag unchanged (got %s)"%brief(twice))

	# ---- case 5c: reconnect after the claim -----------------------------------
	alpha=await rejoin(alpha,port)
	expect(joined(alpha),"case5 alpha reconnects after the claim")
	if not joined(alpha):return false
	expect(view_is(alpha,2,true) and alpha.inventory()==a2,"case5 reconnected alpha: {stage 2, claimed} kept, bag identical, no extra reward (view %s, change %s)"%[str(alpha.own_view()),str(change(a2,alpha.inventory()))])
	var after_rejoin:=await act(alpha,"crab_claim",Crab.CRAB_REST)
	alpha_messages.append(after_rejoin.message)
	expect(crab_is(after_rejoin,false,"claimed",2,true,[]) and alpha.inventory()==a2,"case5 claim after the reconnect is still refused (got %s)"%brief(after_rejoin))
	var done_look:=await act(alpha,"crab_survey",Crab.CRAB_REST)
	alpha_messages.append(done_look.message)
	expect(crab_is(done_look,true,"settled",2,true,[]) and alpha.inventory()==a2,"case2 survey on the settled crab is settled, free (got %s)"%brief(done_look))

	# ---- case 3: beta saw none of it and is independent -----------------------
	await settle([alpha,beta])
	expect(beta.changes>beta_changes+20,"case3 beta stayed connected and kept receiving snapshots through alpha's play (%d)"%(beta.changes-beta_changes))
	expect(quiet_for(beta,beta_mark,alpha_messages),"case3 beta received no action_completed, no crab payload and none of alpha's notices")
	expect(beta.own_view()==null and beta.inventory()==b0,"case3 beta still has no record and an untouched bag after alpha finished (view %s, change %s)"%[str(beta.own_view()),str(change(b0,beta.inventory()))])
	expect(not foreign_crab(beta,alpha) and not foreign_crab(alpha,beta),"case3 neither client sees stone_crab under the other's player entry")
	var seen_alpha:Dictionary=beta.session.snapshot.get("players",{}).get(alpha.session.own_id,{})
	expect(not seen_alpha.is_empty() and not seen_alpha.has("inventory"),"case3 beta sees alpha's public entry without inventory")
	var b_claim0:=await act(beta,"crab_claim",Crab.CRAB_REST)
	expect(crab_is(b_claim0,false,"far",0,false,[]) and beta.count("gold_ore")==0,"case3 beta cannot claim at alpha's rest cell: its own crab is still at (47,22) (got %s)"%brief(b_claim0))
	var b_claim1:=await act(beta,"crab_claim",Crab.CRAB)
	expect(crab_is(b_claim1,false,"waiting",0,false,[]) and beta.count("gold_ore")==0,"case3 beta cannot claim on alpha's progress (got %s)"%brief(b_claim1))
	var b_early:=await act(beta,"crab_repair",Crab.CART)
	expect(crab_is(b_early,false,"too_early",0,false,[]) and beta.inventory()==b0 and beta.own_view()==null,"case3 alpha's mended cart does not count for beta: repair is too_early at beta's stage 0 (got %s)"%brief(b_early))
	var alpha_mark:=alpha.frames.size()
	var beta_mark2:=beta.frames.size()
	var b_look:=await act(beta,"crab_survey",Crab.CRAB)
	expect(crab_is(b_look,true,"look",1,false,["crab_clack"]) and view_is(beta,1,false),"case3 beta: own survey is look (got %s)"%brief(b_look))
	var b_repair:=await act(beta,"crab_repair",Crab.CART)
	expect(crab_is(b_repair,true,"repair",2,false,["crab_hammer","crab_wheel","crab_scuttle"]),"case3 beta: own repair succeeds (got %s)"%brief(b_repair))
	if outcome(b_repair)!="repair":return false
	var b1:=beta.inventory()
	expect(change(b0,b1)=={"plank":-2,"copper_joint":-1} and beta.count("plank")==0 and beta.count("copper_joint")==0 and view_is(beta,2,false),"case3 beta paid its own plank 2 + copper_joint 1 (change %s)"%str(change(b0,b1)))
	var beta_messages:Array=beta.notices(beta_mark2).map(func(f):return str(f.args[0]))
	await settle([alpha,beta])
	expect(quiet_for(alpha,alpha_mark,beta_messages),"case3 alpha received no action_completed, no crab payload and none of beta's notices")
	expect(alpha.inventory()==a2 and view_is(alpha,2,true),"case3 alpha's bag and record are untouched by beta's play (change %s)"%str(change(a2,alpha.inventory())))
	expect(not foreign_crab(beta,alpha) and not foreign_crab(alpha,beta),"case3 after beta's repair neither sees the other's stone_crab")

	# ---- case 3: the cart is solid, the crab cells are walkable ---------------
	for walker:Client in [alpha,beta]:
		expect(await walk(walker,[STAND,BELOW_CART]),"case3 %s walks to the cell below the cart (pos %s)"%[walker.label,str(walker.pos())])
		await push(walker,Vector2(0,-1),1.2)
		expect(walker.cell()!=Crab.CART and walker.pos().y>=23.0 and walker.cell()==Vector2i(45,23),"case3 %s walking up into the cart (45,22) is stopped outside it (pos %s)"%[walker.label,str(walker.pos())])
		expect(await walk(walker,[STAND,ON_REST]) and walker.cell()==Crab.CRAB_REST,"case3 %s can stand on the rest cell (46,22) (pos %s)"%[walker.label,str(walker.pos())])
		await push(walker,Vector2(-1,0),1.2)
		expect(walker.cell()!=Crab.CART and walker.pos().x>=46.0,"case3 %s walking left into the cart from (46,22) is stopped outside it (pos %s)"%[walker.label,str(walker.pos())])
		expect(await go(walker,ON_CRAB) and walker.cell()==Crab.CRAB,"case3 %s can stand on the crab cell (47,22) (pos %s)"%[walker.label,str(walker.pos())])
		expect(await go(walker,STAND),"case3 %s walks back to the standing spot (pos %s)"%[walker.label,str(walker.pos())])
	expect(alpha.inventory()==a2 and beta.inventory()==b1 and view_is(alpha,2,true) and view_is(beta,2,false),"case3 walking around changed no bag and no record")

	# ---- case 8: base B5 behaviour on the same host ---------------------------
	var observed:=await act(alpha,"survey_observe",SURVEY_POINT,"",false)
	expect(observed.replied and observed.ok and observed.crab.is_empty(),"case8 survey_observe at (46,24) is still accepted (got %s)"%brief(observed))
	expect(await wait_until(func():return alpha.seen_pages().get("5",false)==true,3.0),"case8 alpha's own survey record shows page 5 (got %s)"%str(alpha.seen_pages()))
	expect(alpha.inventory()==a2 and view_is(alpha,2,true),"case8 survey_observe did not touch the crab record or bag")
	var miner:=await join("miner",MINER,port)
	expect(joined(miner),"miner joined")
	if not joined(miner):return false
	await settle([miner])
	var m0:=miner.inventory()
	var node_centre:=Vector2(ORE_NODE)+Vector2(0.5,0.5)
	expect(miner.region()==cave and miner.pos().distance_to(node_centre)<=3.2,"case8 miner stands in mine_5 within reach of ore node (28,23) (pos %s)"%str(miner.pos()))
	var struck:=await act(miner,"pick",ORE_NODE,"",false)
	expect(struck.replied and struck.ok and struck.crab.is_empty(),"case8 pick on a B5 ore node is accepted (got %s)"%brief(struck))
	expect(change(m0,miner.inventory())=={"gold_ore":Mines.YIELDS[4],"crystal_sand":1},"case8 pick yields gold_ore +%d and crystal_sand +1 as before (change %s)"%[Mines.YIELDS[4],str(change(m0,miner.inventory()))])
	expect(miner.own_view()==null,"case8 mining gold_ore creates no stone_crab record")
	var cooling:=await act(miner,"pick",ORE_NODE,"",false)
	expect(cooling.replied and not cooling.ok and change(m0,miner.inventory())=={"gold_ore":Mines.YIELDS[4],"crystal_sand":1},"case8 the ore node cooldown still applies (got %s)"%brief(cooling))
	var far_crab:=await act(miner,"crab_survey",Crab.CRAB,"",false)
	expect(far_crab.replied and not far_crab.ok and miner.own_view()==null and (far_crab.crab.is_empty() or outcome(far_crab)=="far"),"case8 crab_survey from the main gallery (out of reach) is refused, no record (got %s)"%brief(far_crab))
	var m1:=miner.inventory()
	await leave(miner)

	# ---- case 6 + 7: host restart on the same save -----------------------------
	short=await join("short",SHORT,port)
	expect(joined(short) and view_is(short,1,false) and short.own_view()!=null and short.inventory()==s0,"case5 short reconnects: stage 1 kept, bag identical")
	var hits:Array=alpha.snapshot_hits+beta.snapshot_hits+short.snapshot_hits+miner.snapshot_hits
	expect(hits.is_empty(),"no snapshot before the restart exposed a foreign stone_crab or raw tokens: %s"%str(hits.slice(0,3)))
	await leave(short)
	await leave(alpha)
	await leave(beta)
	expect(await stop_server(),"case6 host shuts down with a final save")
	var disk=read_save()
	expect(disk is Dictionary,"case6 save file parses")
	if not disk is Dictionary:return false
	expect(validate((disk as Dictionary).duplicate(true)),"case7 the save written by the host re-validates through SaveSchema (JSON round trip from disk)")
	expect(saved_record_is(disk.players.get(ALPHA,{}),2,true) and saved_record_is(disk.players.get(BETA,{}),2,false) and saved_record_is(disk.players.get(SHORT,{}),1,false),"case6 save holds alpha {2,claimed}, beta {2,unclaimed}, short {1,unclaimed} (got %s / %s / %s)"%[str(disk.players.get(ALPHA,{}).get(FIELD)),str(disk.players.get(BETA,{}).get(FIELD)),str(disk.players.get(SHORT,{}).get(FIELD))])
	expect(not (disk.players.get(MINER,{}) as Dictionary).has(FIELD),"case6 save holds no record for the miner")
	expect(ints(disk.players.get(ALPHA,{}).get("inventory",{}))==ints(a2) and ints(disk.players.get(BETA,{}).get("inventory",{}))==ints(b1) and ints(disk.players.get(SHORT,{}).get("inventory",{}))==ints(s0) and ints(disk.players.get(MINER,{}).get("inventory",{}))==ints(m1),"case6 save holds every bag exactly as the clients last saw it")
	var port2:=start_server()
	expect(port2>0,"case6 a new host Session serves the same save file")
	if port2==0:return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	short=await join("short",SHORT,port2)
	expect(joined(alpha) and joined(beta) and joined(short),"case6 alpha, beta and short rejoin the restarted host")
	if not joined(alpha) or not joined(beta) or not joined(short):return false
	await settle([alpha,beta,short])
	expect(alpha.region()==cave and beta.region()==cave and short.region()==cave,"case6 all are back in mine_5")
	expect(view_is(alpha,2,true) and view_is(beta,2,false) and beta.own_view()!=null and view_is(short,1,false) and short.own_view()!=null,"case6 records survive the restart (%s / %s / %s)"%[str(alpha.own_view()),str(beta.own_view()),str(short.own_view())])
	expect(alpha.inventory()==a2 and beta.inventory()==b1 and short.inventory()==s0,"case6 item counts survive the restart, nothing granted by it (changes %s / %s / %s)"%[str(change(a2,alpha.inventory())),str(change(b1,beta.inventory())),str(change(s0,short.inventory()))])
	expect(await go(alpha,STAND) and await go(beta,STAND) and await go(short,STAND),"case6 all stand at the cave spot after the restart")
	var cross:=beta.frames.size()
	var a_after:=await act(alpha,"crab_claim",Crab.CRAB_REST)
	expect(crab_is(a_after,false,"claimed",2,true,[]) and alpha.inventory()==a2,"case6 alpha (already claimed) is still refused after the restart (got %s)"%brief(a_after))
	var a_repair_after:=await act(alpha,"crab_repair",Crab.CART)
	expect(crab_is(a_repair_after,false,"settled",2,true,[]) and alpha.inventory()==a2,"case6 alpha cannot pay for the repair a second time after the restart (got %s)"%brief(a_repair_after))
	expect(beta.completions(cross).is_empty() and beta.payloads(cross).is_empty() and beta.inventory()==b1,"case6 beta received nothing for alpha's post-restart requests")
	var b_gift:=await act(beta,"crab_claim",Crab.CRAB_REST)
	expect(crab_is(b_gift,true,"claim",2,true,["crab_chime"]),"case6 beta (repaired before the restart, not yet claimed) claims after it (got %s)"%brief(b_gift))
	var b2:=beta.inventory()
	expect(change(b1,b2)=={Crab.REWARD_ITEM:Crab.REWARD_COUNT} and view_is(beta,2,true),"case6 beta's claim gave exactly gold_ore +2 (change %s)"%str(change(b1,b2)))
	var b_twice:=await act(beta,"crab_claim",Crab.CRAB_REST)
	expect(crab_is(b_twice,false,"claimed",2,true,[]) and beta.inventory()==b2,"case6 beta's second claim is refused: exactly once (got %s)"%brief(b_twice))
	var s_after:=await act(short,"crab_repair",Crab.CART)
	expect(crab_is(s_after,false,"short",1,false,[]) and ints(s_after.crab.get("missing",{}))=={"plank":1,"copper_joint":1} and short.inventory()==s0,"case6 short is still stage 1 and still short after the restart (got %s)"%brief(s_after))
	await settle([alpha,beta,short])
	expect(alpha.inventory()==a2 and view_is(alpha,2,true) and short.count("gold_ore")==0,"case6 beta's claim touched neither alpha's bag nor short's")
	expect(not foreign_crab(beta,alpha) and not foreign_crab(alpha,beta) and not foreign_crab(short,alpha) and not foreign_crab(alpha,short),"case6 after the restart nobody sees another player's stone_crab")
	var again_seen:=await act(beta,"survey_observe",SURVEY_POINT,"",false)
	expect(again_seen.replied and again_seen.ok and await wait_until(func():return beta.seen_pages().get("5",false)==true,3.0),"case8 survey_observe at (46,24) works for beta on the restarted host (got %s)"%brief(again_seen))
	hits=alpha.snapshot_hits+beta.snapshot_hits+short.snapshot_hits
	expect(hits.is_empty(),"no snapshot after the restart exposed a foreign stone_crab or raw tokens: %s"%str(hits.slice(0,3)))
	await leave(alpha)
	await leave(beta)
	await leave(short)
	expect(await stop_server(),"case6 restarted host shuts down with a final save")
	var disk2=read_save()
	var kept:bool=disk2 is Dictionary and validate((disk2 as Dictionary).duplicate(true))
	if kept:
		kept=saved_record_is(disk2.players.get(ALPHA,{}),2,true) and saved_record_is(disk2.players.get(BETA,{}),2,true) and saved_record_is(disk2.players.get(SHORT,{}),1,false)
		kept=kept and ints(disk2.players[ALPHA].inventory)==ints(a2) and ints(disk2.players[BETA].inventory)==ints(b2) and ints(disk2.players[SHORT].inventory)==ints(s0)
	expect(kept,"case6/7 second save: valid, alpha and beta {2,claimed}, short {1,unclaimed}, bags exact (gold_ore +2 once each)")
	return true

# ---- case 9: adventure world (fixture "adventure", its own host) ------------
func phase_adventure()->bool:
	var cave:=Crab.REGION
	expect(seed_fixture("adventure",5,true,{DELTA:[cave,STAND,{"plank":2,"copper_joint":1}],ECHO:[cave,STAND,{}]}),"case9 SEEDED fixture 'adventure' (world_mode=adventure, picnic, unlocked=5) written and accepted by SaveSchema")
	if save_path.is_empty() or not FileAccess.file_exists(save_path):return false
	var port:=start_server()
	expect(port>0,"case9 host serves fixture 'adventure'")
	if port==0:return false
	var delta:=await join("delta",DELTA,port)
	var echo:=await join("echo",ECHO,port)
	expect(joined(delta) and joined(echo),"case9 delta and echo joined")
	if not joined(delta) or not joined(echo):return false
	await settle([delta,echo])
	expect(str(delta.session.snapshot.get("world_mode",""))=="adventure","case9 snapshot says world_mode adventure (got %s)"%str(delta.session.snapshot.get("world_mode")))
	expect(delta.region()==cave and Crab.near(delta.pos(),Crab.CRAB) and delta.own_view()==null and delta.wtime()>=0.0,"case9 delta stands near the crab with no record (pos %s)"%str(delta.pos()))
	var d0:=delta.inventory()
	var echo_mark:=echo.frames.size()
	var e0:=echo.inventory()
	var messages:Array=[]
	var raw_wait:=await act(delta,"crab_shell",Crab.CRAB,"wait")
	messages.append(raw_wait.message)
	expect(crab_is(raw_wait,false,"too_early",0,false,[]) and no_cycle(raw_wait) and delta.own_view()==null,"case9 crab_shell wait before looking is too_early, no cycle (got %s)"%brief(raw_wait))
	var bad:=await act(delta,"crab_shell",Crab.CRAB,"poke")
	messages.append(bad.message)
	expect(crab_is(bad,false,"invalid",0,false,[]),"case9 crab_shell with an unknown extra is invalid (got %s)"%brief(bad))
	var look:=await act(delta,"crab_survey",Crab.CRAB)
	messages.append(look.message)
	expect(crab_is(look,true,"look",1,false,["crab_clack"]) and view_is(delta,1,false),"case9 survey is look, stage 1 (got %s)"%brief(look))
	if outcome(look)!="look":return false
	var cold_tap:=await act(delta,"crab_shell",Crab.CRAB,"tap")
	messages.append(cold_tap.message)
	expect(crab_is(cold_tap,false,"late",1,false,[]) and no_cycle(cold_tap),"case9 tap with no cycle running is late (got %s)"%brief(cold_tap))

	# reconnect during the wait drops the cycle
	var first:=await act(delta,"crab_shell",Crab.CRAB,"wait")
	messages.append(first.message)
	var open1:=float(first.crab.get("open_at",-1.0))
	expect(crab_is(first,true,"windup",1,false,["crab_rumble"]) and open1>0.0 and is_equal_approx(float(first.crab.get("close_at",-1.0))-open1,Crab.SHELL_WINDOW),"case9 wait starts a cycle: windup, cue crab_rumble, close_at = open_at + 2.5 (got %s)"%brief(first))
	expect(open1>=delta.wtime() and open1<=delta.wtime()+Crab.SHELL_WINDUP+0.05,"case9 open_at is at most 3.0 world seconds ahead of the snapshot clock (open_at %.2f, clock %.2f)"%[open1,delta.wtime()])
	if outcome(first)!="windup":return false
	delta=await rejoin(delta,port)
	expect(joined(delta),"case9 delta reconnects during the wait")
	if not joined(delta):return false
	expect(view_is(delta,1,false) and delta.inventory()==d0 and Crab.near(delta.pos(),Crab.CRAB),"case9 reconnected delta: stage 1 and bag kept, still beside the crab")
	expect(await wait_world(delta,open1+MARGIN) and delta.wtime()<open1+Crab.SHELL_WINDOW-0.5,"case9 the server clock is inside the pre-reconnect window (clock %.2f, window %.2f..%.2f)"%[delta.wtime(),open1,open1+Crab.SHELL_WINDOW])
	var dropped:=await act(delta,"crab_shell",Crab.CRAB,"tap")
	messages.append(dropped.message)
	expect(crab_is(dropped,false,"late",1,false,[]) and no_cycle(dropped),"case9 tap inside the old window after a reconnect is late: the cycle was dropped (got %s)"%brief(dropped))
	expect(view_is(delta,1,false) and delta.inventory()==d0,"case9 the dropped cycle cost nothing (view %s, change %s)"%[str(delta.own_view()),str(change(d0,delta.inventory()))])

	# a full cycle: wait, tap too early, tap inside the window
	var second:=await act(delta,"crab_shell",Crab.CRAB,"wait")
	messages.append(second.message)
	var open2:=float(second.crab.get("open_at",-1.0))
	expect(crab_is(second,true,"windup",1,false,["crab_rumble"]) and open2>open1,"case9 waiting again starts a new cycle (windup, not watching) (got %s)"%brief(second))
	if outcome(second)!="windup":return false
	var watching:=await act(delta,"crab_shell",Crab.CRAB,"wait")
	messages.append(watching.message)
	expect(crab_is(watching,false,"watching",1,false,[]) and is_equal_approx(float(watching.crab.get("open_at",-1.0)),open2),"case9 a second wait during the cycle is watching and keeps open_at (got %s)"%brief(watching))
	var early:=await act(delta,"crab_shell",Crab.CRAB,"tap")
	messages.append(early.message)
	expect(delta.wtime()<open2,"case9 the early tap was sent before open_at on the snapshot clock (clock %.2f, open_at %.2f)"%[delta.wtime(),open2])
	expect(crab_is(early,false,"early",1,false,[]) and is_equal_approx(float(early.crab.get("open_at",-1.0)),open2),"case9 tap before the shell lifts is early and does not cancel the cycle (got %s)"%brief(early))
	expect(view_is(delta,1,false) and delta.inventory()==d0,"case9 the early tap changed nothing (view %s, change %s)"%[str(delta.own_view()),str(change(d0,delta.inventory()))])
	expect(await wait_world(delta,open2+MARGIN),"case9 server clock (snapshot time) passed open_at")
	var soft:=await act(delta,"crab_shell",Crab.CRAB,"tap")
	messages.append(soft.message)
	expect(crab_is(soft,true,"soft",2,false,["crab_soft","crab_wheel","crab_scuttle"]) and no_cycle(soft),"case9 tap inside the window is soft, stage 2, cycle cleared (got %s, clock %.2f, window %.2f..%.2f)"%[brief(soft),delta.wtime(),open2,open2+Crab.SHELL_WINDOW])
	if outcome(soft)!="soft":return false
	expect(view_is(delta,2,false) and delta.inventory()==d0 and delta.count("plank")==2 and delta.count("copper_joint")==1,"case9 the soft-shell route spent no materials (change %s)"%str(change(d0,delta.inventory())))
	var paid:=await act(delta,"crab_repair",Crab.CART)
	messages.append(paid.message)
	expect(crab_is(paid,false,"settled",2,false,[]) and delta.inventory()==d0,"case9 repair after the soft-shell route is settled and spends nothing (got %s)"%brief(paid))
	var gift:=await act(delta,"crab_claim",Crab.CRAB_REST)
	messages.append(gift.message)
	expect(crab_is(gift,true,"claim",2,true,["crab_chime"]),"case9 crab_claim after the soft-shell route succeeds (got %s)"%brief(gift))
	var d1:=delta.inventory()
	expect(change(d0,d1)=={Crab.REWARD_ITEM:Crab.REWARD_COUNT} and view_is(delta,2,true),"case9 the gift is the same gold_ore +2 (change %s)"%str(change(d0,d1)))
	var twice:=await act(delta,"crab_claim",Crab.CRAB_REST)
	messages.append(twice.message)
	expect(crab_is(twice,false,"claimed",2,true,[]) and delta.inventory()==d1,"case9 second claim is refused: once only (got %s)"%brief(twice))

	# echo is independent in the adventure world too
	await settle([delta,echo])
	expect(quiet_for(echo,echo_mark,messages),"case9 echo received no action_completed, no crab payload and none of delta's notices")
	expect(echo.own_view()==null and echo.inventory()==e0 and not foreign_crab(echo,delta) and not foreign_crab(delta,echo),"case9 echo has no record, an untouched bag, and neither sees the other's stone_crab")
	var e_tap:=await act(echo,"crab_shell",Crab.CRAB,"tap")
	expect(crab_is(e_tap,false,"too_early",0,false,[]) and echo.own_view()==null,"case9 echo's own crab is still tucked: tap is too_early (got %s)"%brief(e_tap))
	var hits:Array=delta.snapshot_hits+echo.snapshot_hits
	expect(hits.is_empty(),"case9 no snapshot exposed a foreign stone_crab or raw tokens: %s"%str(hits.slice(0,3)))
	await leave(delta)
	await leave(echo)
	expect(await stop_server(),"case9 adventure host shuts down with a final save")
	var disk=read_save()
	var kept:bool=disk is Dictionary and validate((disk as Dictionary).duplicate(true))
	if kept:
		kept=str(disk.get("world_mode",""))=="adventure" and saved_record_is(disk.players.get(DELTA,{}),2,true) and not (disk.players.get(ECHO,{}) as Dictionary).has(FIELD)
		kept=kept and ints(disk.players[DELTA].inventory)==ints(d1) and ints(disk.players[ECHO].inventory)==ints(e0)
	expect(kept,"case9 adventure save: valid, delta {2,claimed} with materials intact and gold_ore +2, echo without a record")
	return true

## DIRECT World.act, in memory, NO socket and NO save file (labelled as such): the one spot
## no legal save can hold, a player inside the B5 cave while B5 is locked.
func direct_gate()->void:
	var w:=World.new()
	w.save_path=folders.back().path_join("direct-gate-never-written.json")
	w.state["picnic"]=true
	w.add_player(LOCKED,"locked")
	w.active_tokens[LOCKED]=true
	var p:Dictionary=w.state.players[LOCKED]
	p["region"]=Crab.REGION
	p["x"]=STAND.x
	p["y"]=STAND.y
	p.inventory["plank"]=2
	p.inventory["copper_joint"]=1
	var before:Dictionary=w.state.duplicate(true)
	var index:=0
	for attempt:Array in [["crab_survey",Crab.CRAB,""],["crab_repair",Crab.CART,""],["crab_claim",Crab.CRAB,""],["crab_shell",Crab.CRAB,"wait"]]:
		index+=1
		var result:Dictionary=w.act(LOCKED,"crab-net-direct-%d"%index,attempt[0],attempt[1],attempt[2])
		var crab=result.get("crab",{})
		expect(result.get("ok",true)==false and crab is Dictionary and str(crab.get("outcome",""))=="unavailable" and int(crab.get("stage",-1))==0 and crab.get("claimed")==false,"case1 DIRECT World.act (no socket): %s in the B5 cave with unlocked=1 answers unavailable (got %s)"%[attempt[0],str(result)])
	expect(w.state==before and (w.get("_crab_watch") as Dictionary).is_empty() and not FileAccess.file_exists(w.save_path),"case1 DIRECT World.act (no socket): refused gate actions change no state, start no cycle and write no file")

func teardown()->void:
	for c in live:
		if c!=null and is_instance_valid(c.session) and not c.session.shutting_down:
			c.session.shutdown()
	await pause(0.2)
	if server!=null and is_instance_valid(server) and server.world!=null:
		expect(server.shutdown(),"final server shutdown saves cleanly")
	await pause(0.2)
	for c in live:
		if c!=null and is_instance_valid(c.branch):c.branch.queue_free()
	if is_instance_valid(server_branch):server_branch.queue_free()
	await process_frame

func remove_folders()->bool:
	var clean:=not folders.is_empty()
	for folder:String in folders:
		if not DirAccess.dir_exists_absolute(folder):
			clean=false
			continue
		var dir:=DirAccess.open(folder)
		if dir==null:
			clean=false
			continue
		for file in dir.get_files():
			if DirAccess.remove_absolute(folder.path_join(file))!=OK:clean=false
		if DirAccess.remove_absolute(folder)!=OK or DirAccess.dir_exists_absolute(folder):clean=false
	return clean
