extends SceneTree
## B2 害羞菇 (shy mushroom) over a real WebSocket: solo flow, too-early water,
## walk-away cancel, two-client privacy and independence, reconnect, server
## restart from the save file, base B2 actions preserved, availability gate.
##
## LEVEL (same harness as network_sleepy_stone_guardian.gd): one machine, ONE
## Godot process. A real dedicated server Session listens on a free 127.0.0.1
## port with WebSocketMultiplayerPeer; each client Session joins over loopback
## from its own scene branch with its own SceneMultiplayer. Requests, notices,
## action results and snapshots really travel through RPC + WebSocket. Clients
## only read what they received. Not a multi-machine / multi-process test.
##
## FRAMES: raw socket bytes cannot be tapped, so "frame" means every signal a
## client Session emits for an inbound RPC (snapshots via `changed`, `notice`,
## `action_completed`, and any other script signal). Every snapshot is checked
## on arrival for `shy_mushroom` under a foreign player entry and for raw tokens.
##
## CLOCK: the 4 second quiet wait runs on the server's `state.time`. The test
## never touches it: it waits until the snapshot `time` the client received has
## passed `since + WAIT_SECONDS` (plus a small margin). World time only advances
## while at least one client is connected.
##
## SEEDED FIXTURE A (disclosed): picnic=true; mine_depths={unlocked:5,pumped:24};
## players solo/walk/alpha/beta already stand in the B2 east nook (mine_2, about
## (45.5,22.5)); player "gate" stands in mine_1. After the seed everything is
## done by clients: real movement input and Session.perform.
## SEEDED FIXTURE B (disclosed, gate only, second server on a second save):
## picnic=true, mine_depths left at the fresh-world default (unlocked=1), and one
## player placed in mine_1 beside the DOWN ladder: a save ordinary play can
## produce. The earlier version placed that player inside mine_2 while B2 was
## still locked; SaveSchema rightly rejects such a save (a player may not stand
## on a floor that is not open), so it could never be hosted. That protection
## is kept and asserted here. Over the socket the test proves (a) the ordinary
## mine_travel to mine_2 is refused, so the nook cannot be reached, and (b) the
## shy actions answer `unavailable`. The "standing in the nook with unlocked<2"
## case is in-memory only and stays covered by test_shy_mushroom_world.gd
## check_gates (direct World.act); it is not repeated here.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Shy=preload("res://scripts/shy_mushroom.gd")
const Spores=World.SHY_SPORES
const Regions=preload("res://scripts/regions.gd")
const Mines=preload("res://scripts/mine_depths.gd")
const TAG:="SHY_MUSHROOM_NETWORK"
const KEY:="shy-mushroom-net"
const SOLO:="shy-net-solo-token"
const WALK:="shy-net-walk-token"
const ALPHA:="shy-net-alpha-token"
const BETA:="shy-net-beta-token"
const GATE:="shy-net-gate-token"
const LOCKED:="shy-net-locked-token"
const TOKENS:=[SOLO,WALK,ALPHA,BETA,GATE,LOCKED]
const FIELD:="shy_mushroom"
const STAND:=Vector2(45.5,22.5)
const AWAY:=Vector2(45.5,20.5)
const SURVEY_POINT:=Vector2i(44,21)
const PLAIN_CELL:=Vector2i(45,21)
const MARGIN:=0.3

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
						if str(id)!=own and people[id] is Dictionary and people[id].has("shy_mushroom"):
							snapshot_hits.append("snapshot #%d exposes shy_mushroom under foreign player %s"%[changes,str(id)])
				var text:=JSON.stringify(snap)
				for needle:String in needles:
					if text.contains(needle):snapshot_hits.append("snapshot #%d contains %s"%[changes,needle])
			frames.append({"name":signal_name,"args":[]})
		else:
			frames.append({"name":signal_name,"args":args})
	## Frames other than snapshots received since `mark`.
	func others(mark:int) -> Array:
		var out:Array=[]
		for i in range(mark,frames.size()):
			if frames[i].name!="changed":out.append(frames[i])
		return out
	func notices(mark:int) -> Array:
		return others(mark).filter(func(f):return f.name=="notice")
	func completions(mark:int) -> Array:
		return others(mark).filter(func(f):return f.name=="action_completed")
	## Every `shy` payload received since `mark` (any signal, any argument).
	func payloads(mark:int) -> Array:
		var out:Array=[]
		for frame in others(mark):
			for arg in frame.args:
				if arg is Dictionary and arg.get("shy") is Dictionary:out.append(arg.shy)
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
	func inventory()->Dictionary:
		var inv=me().get("inventory",{})
		return (inv as Dictionary).duplicate(true) if inv is Dictionary else {}
	func fiber()->int:
		return int(inventory().get("fiber",0))
	func wtime()->float:
		var value=session.snapshot.get("time")
		return float(value) if (value is float or value is int) else -1.0
	func visible_ids()->Array:
		var ids:Array=session.snapshot.get("players",{}).keys()
		ids.sort()
		return ids
	## The client's own record as its snapshot exposes it (null if absent).
	func own_view():
		var mine=me().get("shy_mushroom")
		return mine if mine is Dictionary else null
	func spore_view()->Dictionary:
		return session.snapshot.get(Spores.VIEW,{})
	func spore_phase()->int:
		return int(spore_view().get("phase",-1))
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
var shy_replies_expected:=0
var shy_replies_with_payload:=0
var base:Dictionary={}
var solo:Client
var walker:Client
var alpha:Client
var beta:Client
var gate:Client
var locked:Client

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL "+label)

func _initialize()->void:
	create_timer(175.0).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("%s watchdog fired before completion"%TAG)
	print("SHY_MUSHROOM_NETWORK_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion (an early stop means a required step did not happen)")
	await teardown()
	if failures==0 and completed:expect(remove_folders(),"temp fixture folders removed")
	else:print("%s kept temp folders for inspection: %s"%[TAG,str(folders)])
	if finished:return
	finished=true
	print("%s replies=%d shy_replies_expected=%d shy_replies_with_payload=%d duration_ms=%d"%[TAG,replies,shy_replies_expected,shy_replies_with_payload,Time.get_ticks_msec()-started])
	if shy_replies_expected>0 and shy_replies_with_payload==0:
		print("%s DIAGNOSIS: no reply ever carried result.shy on action_completed -> shy actions are not wired into World.act / Session._complete_shipping"%TAG)
	print("SHY_MUSHROOM_NETWORK_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

# ---------------------------------------------------------------- fixture --

## placements: token -> [region, preferred standing position]
func seed_fixture(name:String,deep:bool,placements:Dictionary,adventure:=false)->bool:
	var folder:=OS.get_environment("TEMP").path_join("shy-mushroom-net-%s-%s"%[name,Crypto.new().generate_random_bytes(8).hex_encode()])
	if DirAccess.make_dir_recursive_absolute(folder)!=OK:return false
	folders.append(folder)
	save_path=folder.path_join("world.json")
	var w:=World.new()
	w.save_path=save_path
	w.state["picnic"]=true
	if adventure:w.state["world_mode"]="adventure"
	if deep:w.state["mine_depths"]={"unlocked":5,"ready":{},"pumped":24,"hoist":false}
	elif int(w.state.mine_depths.unlocked)>=Shy.DEPTH:return false
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
	w.active_tokens.clear()
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	return parsed is Dictionary and Schema.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

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
		var port:=randi_range(31000,58000)
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
	if c.session.join("ws://127.0.0.1:%d"%port,port,label,KEY)!=OK:return c
	await wait_until(func():return not c.session.own_id.is_empty() and not c.me().is_empty(),8.0)
	return c

func joined(c:Client)->bool:
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty()

func leave(c:Client)->void:
	if c==null or not is_instance_valid(c.session):return
	if not c.session.shutting_down:c.session.shutdown()
	await process_frame
	c.branch.queue_free()

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

## Sends one action and collects what THIS client received for it: the notice and
## any action_completed frame (with its `shy` payload when present).
func act(c:Client,action:String,cell:Vector2i,want_shy:bool=true,extra:="")->Dictionary:
	var mark:=c.frames.size()
	var sequence:int=c.session.perform(action,cell,extra)
	if want_shy:shy_replies_expected+=1
	var replied:=await wait_until(func():return not c.notices(mark).is_empty() or not c.completions(mark).is_empty(),4.0)
	if not replied:return {"replied":false,"ok":false,"message":"","shy":{},"done":0,"matched":false,"result_ok":false,"mark":mark}
	await wait_until(func():return not c.notices(mark).is_empty() and not c.completions(mark).is_empty(),0.7)
	await settle([c])
	var notes:Array=c.notices(mark)
	var done:Array=c.completions(mark)
	var shy:Dictionary={}
	var matched:=false
	var result_ok:=false
	if not done.is_empty():
		var result=done[0].args[2]
		matched=int(done[0].args[0])==sequence and str(done[0].args[1])==action
		if result is Dictionary:
			result_ok=bool(result.get("ok",false))
			if result.get("shy") is Dictionary:shy=result.shy
	replies+=1
	if want_shy and not shy.is_empty():shy_replies_with_payload+=1
	var message:String=str(notes[0].args[0]) if not notes.is_empty() else ""
	var ok_value:bool=bool(notes[0].args[1]) if not notes.is_empty() else result_ok
	return {"replied":true,"ok":ok_value,"message":message,"shy":shy,"done":done.size(),"matched":matched,"result_ok":result_ok,"notices":notes.size(),"mark":mark}

func brief(reply:Dictionary)->String:
	return "{replied=%s ok=%s msg=%s completed=%s shy=%s}"%[str(reply.replied),str(reply.ok),str(reply.message).left(24),str(reply.done),str(reply.shy)]

func outcome(reply:Dictionary)->String:
	return str(reply.shy.get("outcome","<no shy payload>"))

## A shy reply: notice + exactly one correlated action_completed with result.shy.
func shy_is(reply:Dictionary,want_ok:bool,want_outcome:String,want_stage:int,want_claimed:bool,want_cues:Array)->bool:
	if not reply.replied or reply.ok!=want_ok or reply.done!=1 or not reply.matched or reply.result_ok!=want_ok:return false
	var shy:Dictionary=reply.shy
	for field in ["outcome","stage","claimed","remaining","since","x","y","cues"]:
		if not shy.has(field):return false
	if not shy.cues is Array or not shy.claimed is bool:return false
	return str(shy.outcome)==want_outcome and int(shy.stage)==want_stage and shy.claimed==want_claimed and Array(shy.cues)==want_cues

func remaining(reply:Dictionary)->float:
	return float(reply.shy.get("remaining",-1.0))

## Own snapshot record (absent counts as the fresh record).
func view_is(c:Client,want_stage:int,want_claimed:bool)->bool:
	var view=c.own_view()
	if view==null:return want_stage==0 and not want_claimed
	return Shy.valid(view) and int(view.stage)==want_stage and view.claimed==want_claimed

func walk(c:Client,points:Array,seconds:float=10.0)->bool:
	var index:=0
	var deadline:=Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<deadline and index<points.size():
		var last:bool=index==points.size()-1
		var delta:Vector2=points[index]-c.pos()
		if delta.length()<(0.2 if last else 0.4):
			index+=1
			continue
		c.session.input_direction(delta.limit_length() if last else delta.normalized())
		await create_timer(0.05).timeout
	c.session.input_direction(Vector2.ZERO)
	await pause(0.3)
	await settle([c])
	return index>=points.size()

func go(c:Client,target:Vector2)->bool:
	if c.pos().distance_to(target)<0.2:return true
	return await walk(c,[target])

## Waits (real time) until the snapshots this client receives show the server
## clock at or past `target`. Falls back to a real 4.6 s pause without a clock.
func wait_world(c:Client,target:float)->bool:
	if c.wtime()<0.0:
		await pause(Shy.WAIT_SECONDS+0.6)
		return true
	return await wait_until(func():return c.wtime()>=target,20.0)

func peek_time(c:Client,started:Dictionary)->float:
	var since:=float(started.shy.get("since",-1.0))
	if since<0.0:since=c.wtime()
	return since+Shy.WAIT_SECONDS+MARGIN

## start -> (optional early press) -> real wait -> peek. Returns true at stage 1.
func quiet_wait(c:Client,label:String,press_early:bool)->bool:
	var started:=await act(c,"shy_wait",Shy.MUSHROOM)
	expect(shy_is(started,true,"start",0,false,["shy_rustle"]) and is_equal_approx(remaining(started),Shy.WAIT_SECONDS),"%s: first shy_wait is start with remaining 4.0 (got %s)"%[label,brief(started)])
	expect(float(started.shy.get("since",-1.0))>=0.0 and Vector2(float(started.shy.get("x",0.0)),float(started.shy.get("y",0.0))).distance_to(c.pos())<0.3,"%s: start reply carries the anchor (since, x, y at the player) (got %s, pos %s)"%[label,str(started.shy),str(c.pos())])
	if press_early:
		var early:=await act(c,"shy_wait",Shy.MUSHROOM)
		expect(shy_is(early,true,"waiting",0,false,["shy_rustle"]) and remaining(early)>0.0 and remaining(early)<Shy.WAIT_SECONDS,"%s: early press is waiting with 0<remaining<4 (got %s)"%[label,brief(early)])
		expect(view_is(c,0,false),"%s: still stage 0 in own snapshot while waiting (got %s)"%[label,str(c.own_view())])
	expect(await wait_world(c,peek_time(c,started)),"%s: server clock (snapshot time) passed since+4s"%label)
	var peeked:=await act(c,"shy_wait",Shy.MUSHROOM)
	expect(shy_is(peeked,true,"peek",1,false,["shy_peek"]),"%s: press after 4 world seconds is peek, stage 1 (got %s)"%[label,brief(peeked)])
	expect(view_is(c,1,false),"%s: own snapshot shows stage 1 (got %s)"%[label,str(c.own_view())])
	return outcome(peeked)=="peek"

func water_and_claim(c:Client,label:String)->bool:
	var before:=c.fiber()
	var watered:=await act(c,"water",Shy.MUSHROOM)
	expect(shy_is(watered,true,"water",2,false,["shy_splash","shy_open"]),"%s: water at stage 1 opens the mushroom with one action_completed (got %s)"%[label,brief(watered)])
	expect(view_is(c,2,false) and c.fiber()==before,"%s: own snapshot stage 2, unclaimed, no fiber yet (got %s, fiber %d)"%[label,str(c.own_view()),c.fiber()])
	var gift:=await act(c,"shy_claim",Shy.MUSHROOM)
	expect(shy_is(gift,true,"claim",2,true,[]),"%s: shy_claim accepted (got %s)"%[label,brief(gift)])
	expect(c.fiber()==before+Shy.REWARD_COUNT and view_is(c,2,true),"%s: fiber +%d and own snapshot stage 2 / claimed (got fiber %d -> %d, %s)"%[label,Shy.REWARD_COUNT,before,c.fiber(),str(c.own_view())])
	var twice:=await act(c,"shy_claim",Shy.MUSHROOM)
	expect(twice.replied and not twice.ok and outcome(twice)=="claimed" and c.fiber()==before+Shy.REWARD_COUNT,"%s: second shy_claim refused, fiber unchanged (got %s, fiber %d)"%[label,brief(twice),c.fiber()])
	return outcome(gift)=="claim"

## Everything an opened + claimed mushroom may be poked with: nothing is granted.
func poke_finished(c:Client,label:String,want_fiber:int)->void:
	for action:String in ["shy_claim","water","shy_wait"]:
		var again:=await act(c,action,Shy.MUSHROOM)
		expect(again.replied and not again.ok and int(again.shy.get("stage",-1))==2 and again.shy.get("claimed")==true and not outcome(again) in ["start","waiting","peek","water","claim"],"%s: %s on the opened + claimed mushroom is refused (got %s)"%[label,action,brief(again)])
	await settle([c])
	expect(c.fiber()==want_fiber and view_is(c,2,true),"%s: fiber stays %d and record stays stage 2 / claimed (got fiber %d, %s)"%[label,want_fiber,c.fiber(),str(c.own_view())])

func survey_ok(c:Client,label:String)->void:
	var seen:=await act(c,"survey_observe",SURVEY_POINT,false)
	expect(seen.replied and seen.ok and seen.shy.is_empty(),"%s: survey_observe at (44,21) still accepted (got %s)"%[label,brief(seen)])
	expect(await wait_until(func():return c.seen_pages().get("2",false)==true,3.0),"%s: own survey record shows page 2 (got %s)"%[label,str(c.seen_pages())])

func foreign_shy(viewer:Client,subject:Client)->bool:
	var entry=viewer.session.snapshot.get("players",{}).get(subject.session.own_id,{})
	return entry is Dictionary and entry.has(FIELD)

## Frames `watcher` received since `mark` that belong to someone else's shy play.
func quiet_for(watcher:Client,mark:int,actor_messages:Array)->bool:
	var clean:=watcher.completions(mark).is_empty() and watcher.payloads(mark).is_empty()
	for note in watcher.notices(mark):
		if str(note.args[0]) in actor_messages:clean=false
	if not clean:
		for frame in watcher.others(mark):print("  frame to %s: %s %s"%[watcher.label,frame.name,str(frame.args).left(200)])
	return clean

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	var nook:=[Shy.REGION,STAND]
	expect(seed_fixture("a",true,{SOLO:nook,WALK:nook,ALPHA:nook,BETA:nook,GATE:["mine_1",Vector2(38.5,22.5)]}),"SEEDED FIXTURE A written to TEMP and accepted by SaveSchema.validate")
	if save_path.is_empty() or not FileAccess.file_exists(save_path):return false
	var port:=start_server()
	expect(port>0,"server Session hosts on 127.0.0.1 with the websocket transport")
	if port==0:return false

	# ---- 1+2+7. solo: too-early water, base actions, full flow ------------
	solo=await join("solo",SOLO,port)
	expect(joined(solo),"solo joined over loopback")
	if not joined(solo):return false
	var ws:bool=server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and solo.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer
	expect(ws and server.multiplayer.is_server() and not solo.session.multiplayer.is_server() and solo.session.world==null,"real WebSocket server + remote client (client holds no World)")
	print("%s_LABEL machine=single process=single transport=%s loopback=127.0.0.1:%d fixture=SEEDED(picnic,unlocked=5,players placed in mine_2 east nook) clock=real(server state.time read from snapshots)"%[TAG,"websocket" if ws else "UNEXPECTED",port])
	expect(solo.region()==Shy.REGION and solo.visible_ids()==[solo.session.own_id],"solo is alone on B2")
	expect(Shy.near(solo.pos()),"solo stands within reach of the mushroom (pos %s)"%str(solo.pos()))
	expect(solo.wtime()>=0.0,"snapshots carry the server clock `time` (otherwise waits fall back to real pauses)")
	var clock_a:=solo.wtime()
	var real_a:=Time.get_ticks_msec()
	base[SOLO]=solo.fiber()
	expect(view_is(solo,0,false),"solo starts fresh (own view %s)"%str(solo.own_view()))
	# 2. too-early water at stage 0
	var inv_before:=solo.inventory()
	var view_before=solo.own_view()
	var splash:=await act(solo,"water",Shy.MUSHROOM)
	expect(shy_is(splash,false,"too_early",0,false,["shy_rustle"]),"solo: water at stage 0 is refused as too_early with a rustle cue (got %s)"%brief(splash))
	expect(solo.own_view()==view_before and view_is(solo,0,false),"solo: snapshot record unchanged by the too-early water (%s -> %s)"%[str(view_before),str(solo.own_view())])
	expect(solo.inventory()==inv_before,"solo: inventory unchanged by the too-early water")
	var hidden:=await act(solo,"shy_claim",Shy.MUSHROOM)
	expect(hidden.replied and not hidden.ok and outcome(hidden)=="hidden" and solo.fiber()==base[SOLO],"solo: shy_claim before opening is refused (got %s)"%brief(hidden))
	# 7. base B2 actions before opening
	await survey_ok(solo,"solo before opening")
	var plain:=await act(solo,"water",PLAIN_CELL,false)
	expect(plain.replied and not plain.ok and plain.done==0 and plain.shy.is_empty(),"solo: water on a non-mushroom mine_2 cell keeps the base rejection, no action_completed, no shy (got %s)"%brief(plain))
	print("%s INFO base water rejection on %s: %s"%[TAG,str(PLAIN_CELL),plain.message])
	expect(view_is(solo,0,false) and solo.inventory()==inv_before,"solo: base actions did not touch the shy record or inventory")
	# 1. full flow
	if not await quiet_wait(solo,"solo",true):
		print("%s stopped: solo never reached the peek"%TAG)
		return false
	var real_ms:=Time.get_ticks_msec()-real_a
	if clock_a>=0.0:print("%s INFO world clock advanced %.2f s in %.2f real s"%[TAG,solo.wtime()-clock_a,real_ms/1000.0])
	if not await water_and_claim(solo,"solo"):return false
	expect(solo.fiber()-int(base[SOLO])==Shy.REWARD_COUNT,"solo: fiber delta is exactly %d"%Shy.REWARD_COUNT)
	await survey_ok(solo,"solo after opening")
	var plain_after:=await act(solo,"water",PLAIN_CELL,false)
	expect(plain_after.replied and not plain_after.ok and plain_after.done==0 and plain_after.message==plain.message,"solo: base water rejection is the same after opening (got %s)"%brief(plain_after))
	expect(solo.snapshot_hits.is_empty(),"solo: no snapshot carried raw tokens %s"%str(solo.snapshot_hits.slice(0,3)))
	await leave(solo)

	# ---- 3. walk-away cancel / restart ------------------------------------
	walker=await join("walk",WALK,port)
	expect(joined(walker),"walker joined")
	if not joined(walker):return false
	base[WALK]=walker.fiber()
	expect(await go(walker,STAND),"walker stands at the nook spot")
	var w_start:=await act(walker,"shy_wait",Shy.MUSHROOM)
	expect(shy_is(w_start,true,"start",0,false,["shy_rustle"]),"walker: start (got %s)"%brief(w_start))
	var anchor:=walker.pos()
	expect(await go(walker,AWAY) and walker.pos().distance_to(anchor)>Shy.DRIFT,"walker really walks more than 0.75 tiles away (now %s, anchor %s)"%[str(walker.pos()),str(anchor)])
	var far:=await act(walker,"shy_wait",Shy.MUSHROOM)
	expect(far.replied and not far.ok and outcome(far)=="far","walker: shy_wait out of reach is refused as far (got %s)"%brief(far))
	expect(await go(walker,anchor) and walker.pos().distance_to(anchor)<Shy.DRIFT,"walker walks back onto the old anchor (now %s)"%str(walker.pos()))
	expect(await wait_world(walker,peek_time(walker,w_start)),"walker: more than 4 world seconds passed since the cancelled start")
	var w_again:=await act(walker,"shy_wait",Shy.MUSHROOM)
	expect(shy_is(w_again,true,"start",0,false,["shy_rustle"]) and is_equal_approx(remaining(w_again),Shy.WAIT_SECONDS),"walker: after walking away the next press is start again with remaining 4.0, not peek (got %s)"%brief(w_again))
	expect(view_is(walker,0,false) and walker.fiber()==base[WALK],"walker: cancel cost nothing (record %s, fiber %d)"%[str(walker.own_view()),walker.fiber()])
	expect(await wait_world(walker,peek_time(walker,w_again)),"walker: waited 4 world seconds after the restart")
	var w_peek:=await act(walker,"shy_wait",Shy.MUSHROOM)
	expect(shy_is(w_peek,true,"peek",1,false,["shy_peek"]),"walker: peek after the restarted wait (got %s)"%brief(w_peek))
	var w_peeking:=await act(walker,"shy_wait",Shy.MUSHROOM)
	expect(w_peeking.replied and w_peeking.ok and outcome(w_peeking)=="peeking" and int(w_peeking.shy.get("stage",-1))==1,"walker: pressing again at stage 1 only reminds to water (got %s)"%brief(w_peeking))
	if outcome(w_peek)=="peek":await water_and_claim(walker,"walker")
	expect(walker.fiber()-int(base[WALK])==Shy.REWARD_COUNT,"walker: fiber delta is exactly %d"%Shy.REWARD_COUNT)
	await leave(walker)

	# ---- 8a. gate: another mine level --------------------------------------
	gate=await join("gate",GATE,port)
	expect(joined(gate) and gate.region()=="mine_1","gate client stands in mine_1 (region %s)"%(gate.region() if gate!=null else "?"))
	if joined(gate):
		var gate_fiber:=gate.fiber()
		for action:String in ["shy_wait","shy_claim"]:
			var refused:=await act(gate,action,Shy.MUSHROOM)
			expect(refused.replied and not refused.ok and not outcome(refused) in ["start","waiting","peek","claim"],"gate: %s from mine_1 is refused (got %s)"%[action,brief(refused)])
		var gate_water:=await act(gate,"water",Shy.MUSHROOM,false)
		expect(gate_water.replied and not gate_water.ok and gate_water.shy.is_empty() and gate_water.done==0,"gate: water at (46,23) in mine_1 is the base rejection, not routed to the mushroom (got %s)"%brief(gate_water))
		expect(view_is(gate,0,false) and gate.own_view()==null and gate.fiber()==gate_fiber,"gate: no record, no fiber (view %s)"%str(gate.own_view()))
	await leave(gate)

	# ---- 4+5. alpha and beta together; alpha reconnects three times --------
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	expect(joined(alpha) and joined(beta),"alpha and beta joined")
	if not joined(alpha) or not joined(beta):return false
	await settle([alpha,beta])
	var pair:=[alpha.session.own_id,beta.session.own_id]
	pair.sort()
	expect(alpha.visible_ids()==pair and beta.visible_ids()==pair and alpha.session.own_id!=beta.session.own_id,"both stand on B2 and see each other under distinct public ids")
	expect(alpha.session.own_id!=ALPHA and beta.session.own_id!=BETA,"public ids are not the profile tokens")
	expect(await go(alpha,STAND) and await go(beta,STAND),"both stand at the nook spot")
	base[ALPHA]=alpha.fiber()
	base[BETA]=beta.fiber()
	var beta_mark:=beta.frames.size()
	var beta_changes:=beta.changes
	var alpha_messages:Array=[]
	# 5a. mid-wait disconnect
	var a_start:=await act(alpha,"shy_wait",Shy.MUSHROOM)
	alpha_messages.append(a_start.message)
	expect(shy_is(a_start,true,"start",0,false,["shy_rustle"]),"alpha: start (got %s)"%brief(a_start))
	var a_pos:=alpha.pos()
	var a_peek_at:=peek_time(beta,a_start)
	await leave(alpha)
	expect(await wait_until(func():return int(beta.session.snapshot.get("room_population",0))==1,4.0),"server sees alpha leave mid-wait")
	alpha=await join("alpha",ALPHA,port)
	expect(joined(alpha),"alpha reconnects mid-wait with the same token")
	if not joined(alpha):return false
	await settle([alpha])
	expect(alpha.pos().distance_to(a_pos)<Shy.DRIFT and view_is(alpha,0,false),"reconnected alpha is still on the old anchor at stage 0 (pos %s, was %s)"%[str(alpha.pos()),str(a_pos)])
	expect(await wait_world(alpha,a_peek_at),"more than 4 world seconds passed since alpha's pre-disconnect start")
	var a_restart:=await act(alpha,"shy_wait",Shy.MUSHROOM)
	alpha_messages.append(a_restart.message)
	expect(shy_is(a_restart,true,"start",0,false,["shy_rustle"]) and is_equal_approx(remaining(a_restart),Shy.WAIT_SECONDS),"alpha after mid-wait reconnect: next press is start with the full 4.0, not peek (got %s)"%brief(a_restart))
	expect(await wait_world(alpha,peek_time(alpha,a_restart)),"alpha waited 4 world seconds after the restart")
	var a_peek:=await act(alpha,"shy_wait",Shy.MUSHROOM)
	alpha_messages.append(a_peek.message)
	expect(shy_is(a_peek,true,"peek",1,false,["shy_peek"]),"alpha: peek (got %s)"%brief(a_peek))
	if outcome(a_peek)!="peek":return false
	# 5b. reconnect at stage 1
	await leave(alpha)
	expect(await wait_until(func():return int(beta.session.snapshot.get("room_population",0))==1,4.0),"server sees alpha leave at stage 1")
	alpha=await join("alpha",ALPHA,port)
	expect(joined(alpha),"alpha reconnects at stage 1")
	if not joined(alpha):return false
	await settle([alpha,beta])
	expect(view_is(alpha,1,false) and alpha.own_view()!=null and alpha.fiber()==base[ALPHA],"reconnected alpha still sees stage 1 (got %s)"%str(alpha.own_view()))
	expect(view_is(beta,0,false) and not foreign_shy(beta,alpha),"beta: own record still fresh and alpha's entry carries no shy_mushroom (own %s)"%str(beta.own_view()))
	var a_water:=await act(alpha,"water",Shy.MUSHROOM)
	alpha_messages.append(a_water.message)
	expect(shy_is(a_water,true,"water",2,false,["shy_splash","shy_open"]),"alpha: water after the stage-1 reconnect opens the mushroom (got %s)"%brief(a_water))
	var a_claim:=await act(alpha,"shy_claim",Shy.MUSHROOM)
	alpha_messages.append(a_claim.message)
	expect(shy_is(a_claim,true,"claim",2,true,[]) and alpha.fiber()==int(base[ALPHA])+Shy.REWARD_COUNT,"alpha: claim gives +%d fiber (got %s, fiber %d)"%[Shy.REWARD_COUNT,brief(a_claim),alpha.fiber()])
	# duplicate transport delivery of the same sequence is dropped
	var replay_mark:=alpha.frames.size()
	alpha.session.request_action.rpc_id(1,alpha.session.counter,"shy_claim",Shy.MUSHROOM,"",alpha.region(),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha])
	expect(alpha.others(replay_mark).is_empty() and alpha.fiber()==int(base[ALPHA])+Shy.REWARD_COUNT,"replayed claim sequence is dropped: no second reply, no second reward")
	# 5c. reconnect after the claim
	await leave(alpha)
	expect(await wait_until(func():return int(beta.session.snapshot.get("room_population",0))==1,4.0),"server sees alpha leave after the claim")
	alpha=await join("alpha",ALPHA,port)
	expect(joined(alpha),"alpha reconnects after the claim")
	if not joined(alpha):return false
	await settle([alpha,beta])
	expect(view_is(alpha,2,true) and alpha.fiber()==int(base[ALPHA])+Shy.REWARD_COUNT,"reconnected alpha: claimed stays, fiber still +%d (got %s, fiber %d)"%[Shy.REWARD_COUNT,str(alpha.own_view()),alpha.fiber()])
	var a_again:=await act(alpha,"shy_claim",Shy.MUSHROOM)
	alpha_messages.append(a_again.message)
	expect(a_again.replied and not a_again.ok and outcome(a_again)=="claimed" and alpha.fiber()==int(base[ALPHA])+Shy.REWARD_COUNT,"reconnected alpha: claim again fails, fiber unchanged (got %s)"%brief(a_again))
	# 4. beta saw none of it
	expect(beta.changes>beta_changes+20,"beta stayed connected and kept receiving snapshots through alpha's play (%d)"%(beta.changes-beta_changes))
	expect(quiet_for(beta,beta_mark,alpha_messages),"beta received no action_completed, no shy payload and none of alpha's notices")
	expect(view_is(beta,0,false) and beta.fiber()==base[BETA],"beta: own record still stage 0 / absent and fiber unchanged after alpha finished (own %s, fiber %d)"%[str(beta.own_view()),beta.fiber()])
	expect(not foreign_shy(beta,alpha) and not foreign_shy(alpha,beta),"neither client sees shy_mushroom under the other's player entry")
	var seen_alpha:Dictionary=beta.session.snapshot.get("players",{}).get(alpha.session.own_id,{})
	expect(not seen_alpha.is_empty() and not seen_alpha.has("inventory"),"beta sees alpha's public entry without inventory")
	var beta_early:=await act(beta,"water",Shy.MUSHROOM)
	expect(shy_is(beta_early,false,"too_early",0,false,["shy_rustle"]),"beta: alpha's open mushroom does not open beta's (water is too_early) (got %s)"%brief(beta_early))
	var beta_hidden:=await act(beta,"shy_claim",Shy.MUSHROOM)
	expect(beta_hidden.replied and not beta_hidden.ok and outcome(beta_hidden)=="hidden" and beta.fiber()==base[BETA],"beta cannot claim on alpha's progress (got %s)"%brief(beta_hidden))
	# beta completes independently; alpha receives nothing of it
	var alpha_mark:=alpha.frames.size()
	var beta_mark2:=beta.frames.size()
	var beta_done:=await quiet_wait(beta,"beta",true)
	if beta_done:beta_done=await water_and_claim(beta,"beta")
	var beta_messages:Array=beta.notices(beta_mark2).map(func(f):return str(f.args[0]))
	await settle([alpha,beta])
	expect(beta_done and beta.fiber()-int(base[BETA])==Shy.REWARD_COUNT,"beta completed independently: fiber delta exactly %d (got %d)"%[Shy.REWARD_COUNT,beta.fiber()-int(base[BETA])])
	expect(quiet_for(alpha,alpha_mark,beta_messages),"alpha received no action_completed, no shy payload and none of beta's notices")
	expect(view_is(alpha,2,true) and alpha.fiber()==int(base[ALPHA])+Shy.REWARD_COUNT,"alpha unaffected by beta's play: still stage 2 / claimed, +%d"%Shy.REWARD_COUNT)
	expect(not foreign_shy(beta,alpha) and not foreign_shy(alpha,beta),"after both finished, neither sees the other's shy_mushroom")
	await survey_ok(beta,"beta after opening")
	if not beta_done:return false

	# ---- 6. server restart on the saved file -------------------------------
	expect(alpha.snapshot_hits.is_empty() and beta.snapshot_hits.is_empty(),"no snapshot before the restart exposed a foreign shy_mushroom or raw tokens: %s"%str((alpha.snapshot_hits+beta.snapshot_hits).slice(0,3)))
	await leave(alpha)
	await leave(beta)
	expect(await stop_server(),"server shuts down with a final save")
	var disk=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	expect(disk is Dictionary,"save file parses")
	if not disk is Dictionary:return false
	expect(Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"saved world passes SaveSchema")
	for token:String in [SOLO,WALK,ALPHA,BETA]:
		var person:Dictionary=disk.players.get(token,{})
		var saved=person.get(FIELD)
		expect(saved is Dictionary and Shy.valid(saved) and int(saved.stage)==2 and saved.claimed==true,"save holds %s's record {stage 2, claimed} with exactly two fields (got %s)"%[token.get_slice("-",2),str(saved)])
		expect(int(person.get("inventory",{}).get("fiber",0))==int(base[token])+Shy.REWARD_COUNT,"save holds %s's fiber at base +%d"%[token.get_slice("-",2),Shy.REWARD_COUNT])
	expect(not (disk.players.get(GATE,{}) as Dictionary).has(FIELD),"save holds no record for the gate player")
	var port2:=start_server()
	expect(port2>0,"a new server Session hosts the same save")
	if port2==0:return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	expect(joined(alpha) and joined(beta),"both rejoin the restarted server")
	if not joined(alpha) or not joined(beta):return false
	await settle([alpha,beta])
	expect(alpha.region()==Shy.REGION and beta.region()==Shy.REGION,"both are back on B2")
	expect(view_is(alpha,2,true) and view_is(beta,2,true),"records survive the restart (%s / %s)"%[str(alpha.own_view()),str(beta.own_view())])
	expect(alpha.fiber()==int(base[ALPHA])+Shy.REWARD_COUNT and beta.fiber()==int(base[BETA])+Shy.REWARD_COUNT,"fiber counts survive the restart (%d / %d)"%[alpha.fiber(),beta.fiber()])
	expect(await go(alpha,STAND) and await go(beta,STAND),"both stand at the nook spot after the restart")
	var cross_a:=alpha.frames.size()
	await poke_finished(beta,"beta after restart",int(base[BETA])+Shy.REWARD_COUNT)
	expect(alpha.completions(cross_a).is_empty() and alpha.payloads(cross_a).is_empty(),"alpha received nothing for beta's post-restart pokes")
	await poke_finished(alpha,"alpha after restart",int(base[ALPHA])+Shy.REWARD_COUNT)
	await survey_ok(alpha,"alpha after restart")
	expect(not foreign_shy(beta,alpha) and not foreign_shy(alpha,beta),"after the restart neither sees the other's shy_mushroom")
	expect(alpha.snapshot_hits.is_empty() and beta.snapshot_hits.is_empty(),"no snapshot after the restart exposed a foreign shy_mushroom or raw tokens: %s"%str((alpha.snapshot_hits+beta.snapshot_hits).slice(0,3)))
	await leave(alpha)
	await leave(beta)
	expect(await stop_server(),"restarted server shuts down with a final save")
	var disk2=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	var kept:=disk2 is Dictionary
	if kept:
		for token:String in [SOLO,WALK,ALPHA,BETA]:
			var person2:Dictionary=disk2.players.get(token,{})
			var saved2=person2.get(FIELD,{})
			if not (Shy.valid(saved2) and int(saved2.stage)==2 and saved2.claimed==true and int(person2.get("inventory",{}).get("fiber",0))==int(base[token])+Shy.REWARD_COUNT):kept=false
	expect(kept,"second save still holds four finished records and exactly +%d fiber each"%Shy.REWARD_COUNT)

	# ---- 8b. gate: B2 not opened yet (SEEDED FIXTURE B, valid save, new server) -
	var ladder:=Vector2(Mines.DOWN)+Vector2(-0.5,0.5)
	expect(seed_fixture("b",false,{LOCKED:["mine_1",ladder]}),"SEEDED FIXTURE B (unlocked=1, player in mine_1 beside the DOWN ladder) written and accepted by SaveSchema.validate")
	if save_path.is_empty() or not FileAccess.file_exists(save_path):return false
	# The game protection the old fixture tripped over: a save that puts a player
	# on a floor that is not open is rejected. Kept, and checked on this very save.
	var illegal=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	var protected:bool=illegal is Dictionary and illegal.get("players",{}).has(LOCKED)
	if protected:
		illegal.players[LOCKED]["region"]=Shy.REGION
		illegal.players[LOCKED]["x"]=STAND.x
		illegal.players[LOCKED]["y"]=STAND.y
		protected=not Schema.validate(illegal,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)
	expect(protected,"SaveSchema still rejects the same save once the player is moved into mine_2 while unlocked=1")
	var port3:=start_server()
	expect(port3>0,"gate server hosts fixture B")
	if port3==0:return false
	locked=await join("locked",LOCKED,port3)
	expect(joined(locked),"locked client joined")
	if not joined(locked):return false
	await settle([locked])
	var locked_pos:=locked.pos()
	expect(locked.region()=="mine_1" and locked_pos.distance_to(Vector2(Mines.DOWN)+Vector2(0.5,0.5))<=2.0,"locked client stands in mine_1 beside the DOWN ladder (region %s pos %s)"%[locked.region(),str(locked_pos)])
	var locked_fiber:=locked.fiber()
	var locked_inv:=locked.inventory()
	var epoch:=int(locked.me().get("travel_epoch",0))
	# (a) the ordinary way down is refused: B2 cannot be reached before it is opened.
	var descend_mark:=locked.frames.size()
	locked.session.perform("mine_travel",Mines.DOWN,Shy.REGION)
	expect(await wait_until(func():return not locked.notices(descend_mark).is_empty(),4.0),"locked: mine_travel to mine_2 is answered with a notice")
	await settle([locked])
	var descend_notes:Array=locked.notices(descend_mark)
	var descend_ok:bool=not descend_notes.is_empty() and bool(descend_notes[0].args[1])
	expect(not descend_notes.is_empty() and not descend_ok and locked.completions(descend_mark).is_empty(),"locked: mine_travel DOWN to mine_2 with unlocked=1 is refused, no action_completed (got %s)"%str(descend_notes.map(func(f):return f.args.slice(0,2))))
	expect(locked.region()=="mine_1" and int(locked.me().get("travel_epoch",0))==epoch and locked.pos().distance_to(locked_pos)<0.05,"locked: still in mine_1 at the same spot and travel epoch after the refused descent (region %s pos %s)"%[locked.region(),str(locked.pos())])
	if not descend_notes.is_empty():print("%s INFO locked mine_travel -> ok=%s msg=%s"%[TAG,str(descend_ok),str(descend_notes[0].args[0])])
	# (b) the shy actions are refused. No mine_1 floor lies within the generic
	# reach of (46,23) (B1 has no east nook), so the host's ordinary reach guard
	# answers before the mushroom handler: a refusal with no shy payload at all.
	for action:String in ["shy_wait","shy_claim"]:
		var refused:=await act(locked,action,Shy.MUSHROOM,false)
		expect(refused.replied and not refused.ok and not refused.result_ok and (refused.shy.is_empty() or outcome(refused)=="unavailable"),"locked: %s with unlocked=1 is refused over the socket with no mushroom progress (got %s)"%[action,brief(refused)])
		print("%s INFO locked %s -> outcome=%s msg=%s"%[TAG,action,outcome(refused),refused.message])
	var locked_water:=await act(locked,"water",Shy.MUSHROOM,false)
	expect(locked_water.replied and not locked_water.ok and locked_water.shy.is_empty() and locked_water.done==0,"locked: water on (46,23) is the base rejection, not routed to the mushroom while unlocked=1 (got %s)"%brief(locked_water))
	expect(await wait_world(locked,locked.wtime()+Shy.WAIT_SECONDS+MARGIN),"locked: more than 4 world seconds pass")
	var locked_late:=await act(locked,"shy_wait",Shy.MUSHROOM,false)
	expect(locked_late.replied and not locked_late.ok and (locked_late.shy.is_empty() or outcome(locked_late)=="unavailable"),"locked: a later shy_wait is still refused, no hidden wait was started (got %s)"%brief(locked_late))
	expect(locked.own_view()==null and locked.fiber()==locked_fiber and locked.inventory()==locked_inv,"locked: no record and unchanged inventory (view %s)"%str(locked.own_view()))
	expect(locked.snapshot_hits.is_empty(),"locked: no snapshot carried raw tokens %s"%str(locked.snapshot_hits.slice(0,3)))
	await leave(locked)
	expect(await stop_server(),"gate server shuts down with a final save")
	var disk3=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	var untouched:bool=disk3 is Dictionary and Schema.validate(disk3.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)
	if untouched:
		var person3:Dictionary=disk3.players.get(LOCKED,{})
		untouched=str(person3.get("region",""))=="mine_1" and not person3.has(FIELD) and int(disk3.mine_depths.unlocked)==1 and int(person3.get("inventory",{}).get("fiber",0))==locked_fiber
	expect(untouched,"fixture B save after play: valid, player still in mine_1, unlocked=1, no shy record, fiber unchanged")
	direct_gate()
	return await adventure_spores()

func adventure_spores()->bool:
	var east:=Vector2(46.5,22.5)
	var west:=Vector2(45.5,22.5)
	if not seed_fixture("spores",true,{ALPHA:[Shy.REGION,east],BETA:[Shy.REGION,east]},true):return false
	var port:=start_server()
	if port==0:return false
	alpha=await join("alpha_spore",ALPHA,port)
	beta=await join("beta_spore",BETA,port)
	if not joined(alpha) or not joined(beta):return false
	expect(alpha.session.own_id!=beta.session.own_id and alpha.spore_view().is_empty() and beta.spore_view().is_empty(),"Adventure starts with two distinct players and no hazards")
	var alpha_fiber:=alpha.fiber()
	var beta_fiber:=beta.fiber()
	var reply:=await act(alpha,Spores.ACTION,Shy.MUSHROOM,false,Spores.ENTER)
	expect(reply.ok and reply.matched and reply.result_ok,"Alpha starts a challenge over the socket")
	expect(alpha.spore_phase()==Spores.Phase.WARNING and alpha.spore_view().get("lane")==46.5 and beta.spore_view().is_empty(),"Only Alpha sees the first warning")
	expect(await go(alpha,west),"Alpha walks across to the left lane")
	reply=await act(beta,Spores.ACTION,Shy.MUSHROOM,false,Spores.ENTER)
	expect(reply.ok and reply.matched and reply.result_ok,"Beta starts an independent challenge")
	expect(beta.spore_phase()==Spores.Phase.WARNING and alpha.spore_view()!=beta.spore_view(),"Each client receives a separate timed view")
	expect(await wait_until(func():return alpha.spore_phase()==Spores.Phase.WARNING and alpha.spore_view().get("wave")==1,6.0),"Alpha sees the warning on the other lane")
	expect(await go(alpha,east),"Alpha walks back to the right lane")
	expect(await wait_until(func():return beta.spore_phase()==Spores.Phase.MISSED,4.0),"Beta stays in the lane and gets hit")
	expect(await wait_until(func():return alpha.spore_phase()==Spores.Phase.FINISHED,6.0),"Alpha can finish despite Beta being hit")
	expect(beta.fiber()==beta_fiber and view_is(beta,0,false),"A miss costs nothing and gives no progress")
	reply=await act(beta,Spores.ACTION,Shy.MUSHROOM,false,Spores.FINISH)
	expect(reply.replied and reply.matched and not reply.result_ok,"Beta cannot finish after a miss")
	reply=await act(alpha,Spores.ACTION,Shy.MUSHROOM,false,Spores.FINISH)
	expect(reply.ok and reply.matched and reply.result_ok and view_is(alpha,2,false),"Alpha earns the personal gift")
	expect(not foreign_shy(beta,alpha) and not foreign_shy(alpha,beta) and alpha.snapshot_hits.is_empty() and beta.snapshot_hits.is_empty(),"The private stages and profile tokens stay hidden")
	await leave(alpha)
	await leave(beta)
	expect(await stop_server(),"Stop the host with one unclaimed gift")
	port=start_server()
	if port==0:return false
	alpha=await join("alpha_spore_rejoin",ALPHA,port)
	beta=await join("beta_spore_rejoin",BETA,port)
	if not joined(alpha) or not joined(beta):return false
	expect(view_is(alpha,2,false) and view_is(beta,0,false) and alpha.spore_view().is_empty() and beta.spore_view().is_empty(),"Reconnecting keeps real progress and clears the temporary spore rounds")
	var claim:=await act(alpha,Shy.CLAIM_ACTION,Shy.MUSHROOM)
	expect(claim.ok and claim.result_ok and view_is(alpha,2,true),"Claim succeeds after room restart")
	expect(alpha.fiber()==alpha_fiber+Shy.REWARD_COUNT and beta.fiber()==beta_fiber,"Only Alpha earns the original four fiber")
	var duplicate:=await act(alpha,Shy.CLAIM_ACTION,Shy.MUSHROOM)
	expect(duplicate.replied and not duplicate.ok and alpha.fiber()==alpha_fiber+Shy.REWARD_COUNT,"No duplicate reward after a successful claim")
	await leave(alpha)
	await leave(beta)
	expect(await stop_server(),"Host saves the final claimed state")
	return true

## DIRECT World.act, in memory, NO socket and NO save file (labelled as such):
## the one spot no legal save can hold, a player inside the mine_2 nook while
## unlocked=1. Only the exact `unavailable` outcome is asserted here; the wider
## gate matrix lives in test_shy_mushroom_world.gd check_gates.
func direct_gate()->void:
	var w:=World.new()
	w.save_path=folders.back().path_join("direct-gate-never-written.json")
	w.state["picnic"]=true
	w.add_player(LOCKED,"locked")
	w.active_tokens[LOCKED]=true
	var p:Dictionary=w.state.players[LOCKED]
	p["region"]=Shy.REGION
	p["x"]=STAND.x
	p["y"]=STAND.y
	var before:Dictionary=w.state.duplicate(true)
	var index:=0
	for action:String in ["shy_wait","shy_claim"]:
		index+=1
		var result:Dictionary=w.act(LOCKED,"shy-net-direct-%d"%index,action,Shy.MUSHROOM,"")
		var shy=result.get("shy",{})
		expect(result.get("ok",true)==false and shy is Dictionary and str(shy.get("outcome",""))=="unavailable" and int(shy.get("stage",-1))==0 and shy.get("claimed")==false,"DIRECT World.act (no socket): %s in the mine_2 nook with unlocked=1 answers unavailable (got %s)"%[action,str(result)])
	expect(w.state==before and (w.get("_shy_watch") as Dictionary).is_empty() and not FileAccess.file_exists(w.save_path),"DIRECT World.act (no socket): refused gate actions change no state, start no wait and write no file")

func teardown()->void:
	var everyone:=[solo,walker,alpha,beta,gate,locked]
	for c in everyone:
		if c!=null and is_instance_valid(c.session) and not c.session.shutting_down:
			c.session.shutdown()
	await pause(0.2)
	if server!=null and is_instance_valid(server) and server.world!=null:
		expect(server.shutdown(),"final server shutdown saves cleanly")
	await pause(0.2)
	for c in everyone:
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
