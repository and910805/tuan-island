extends SceneTree
## B4 打瞌睡石像 over a real WebSocket: solo solve, two-client privacy and
## independence, reconnect and server-restart persistence.
## Written against the server contract BEFORE the wiring landed, so it is expected
## to fail until World/Session/SaveSchema handle the guardian actions.
##
## LEVEL (same harness as test_mine_deep_session.gd): one machine, ONE Godot
## process. A real dedicated server Session listens on a free 127.0.0.1 port with
## WebSocketMultiplayerPeer; each client Session joins over loopback from its own
## scene branch with its own SceneMultiplayer. Requests, notices, action results
## and snapshots really travel through RPC + WebSocket. Clients only read what
## they received. This is not a multi-machine or multi-process test.
##
## FRAMES: the test cannot tap raw socket bytes, so "frame" means every signal a
## client Session emits for an inbound RPC (all script signals are recorded:
## snapshots via `changed`, `notice`, `action_completed`, and any signal added
## later). Every snapshot is searched on arrival for hum-order text.
##
## SEEDED FIXTURE (disclosed): picnic=true; mine_depths={unlocked:5,pumped:24};
## players solo/alpha/beta already stand in the B4 north cave (mine_4). After the
## seed everything is done by the clients: real movement input and
## Session.perform. The hum order is always learned from the guardian_listen
## reply, never computed by the test.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Guardian=preload("res://scripts/sleepy_stone_guardian.gd")
const Trial=World.GUARDIAN_TRIAL
const Regions=preload("res://scripts/regions.gd")
const KEY:="sleepy-guardian-net"
const SOLO:="guardian-net-solo-token"
const ALPHA:="guardian-net-alpha-token"
const BETA:="guardian-net-beta-token"
const TOKENS:=[SOLO,ALPHA,BETA]
const START:=Vector2(34.5,13.5)
const LANE_Y:=12.5
const SPOT_GUARDIAN:=Vector2(34.5,11.5)
const SPOT_BELLS:=[Vector2(33.5,11.5),Vector2(34.5,11.5),Vector2(36.5,12.5)]
const UNWIRED_MESSAGE:="請選擇工具後再試一次"

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
			var text:=JSON.stringify(args[0])
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
	## Guardian result payloads received since `mark` (any signal, any argument).
	func payloads(mark:int) -> Array:
		var out:Array=[]
		for frame in others(mark):
			for arg in frame.args:
				if arg is Dictionary and arg.get("guardian") is Dictionary:out.append(arg.guardian)
		return out
	func me()->Dictionary:
		var people=session.snapshot.get("players",{})
		if not people is Dictionary or session.own_id.is_empty():return {}
		return people.get(session.own_id,{})
	func region()->String:
		return str(session.snapshot.get("region_id",""))
	func trial_view()->Dictionary:
		return session.snapshot.get(Trial.KEY,{})
	func trial_phase()->int:
		return int(trial_view().get("phase",-1))
	func pos()->Vector2:
		var p:=me()
		return Vector2(float(p.get("x",-99.0)),float(p.get("y",-99.0)))
	func sand()->int:
		var inv=me().get("inventory",{})
		return int(inv.get("crystal_sand",0)) if inv is Dictionary else -1
	func visible_ids()->Array:
		var ids:Array=session.snapshot.get("players",{}).keys()
		ids.sort()
		return ids
	## The client's own guardian record as the snapshot exposes it (null if absent).
	func own_view():
		var mine=me().get("sleepy_guardian")
		if mine is Dictionary:return mine
		for key in ["sleepy_guardian","own_sleepy_guardian","guardian"]:
			var block=session.snapshot.get(key)
			if block is Dictionary and block.get("own_record") is Dictionary:return block.own_record
			if block is Dictionary and block.has("round"):return block
		return null

var checks:=0
var failures:=0
var serial:=0
var folder:=""
var save_path:=""
var server
var server_branch:Node
var finished:=false
var replies:=0
var replies_unwired:=0
var replies_with_payload:=0
var solo:Client
var alpha:Client
var beta:Client

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL "+label)

func _initialize()->void:
	create_timer(170.0).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("NETWORK_SLEEPY_STONE_GUARDIAN watchdog fired before completion")
	print("NETWORK_SLEEPY_STONE_GUARDIAN checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion (an early stop means a required step did not happen)")
	await teardown()
	if failures==0 and completed:expect(remove_folder(),"temp fixture folder removed")
	else:print("NETWORK_SLEEPY_STONE_GUARDIAN kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("NETWORK_SLEEPY_STONE_GUARDIAN replies=%d unknown_action_replies=%d replies_with_guardian_payload=%d duration_ms=%d"%[replies,replies_unwired,replies_with_payload,Time.get_ticks_msec()-started])
	if replies>0 and replies_unwired==replies:
		print("NETWORK_SLEEPY_STONE_GUARDIAN DIAGNOSIS: every reply was the generic unknown-action notice -> World.act does not handle Guardian.ACTIONS yet (not wired)")
	elif replies>0 and replies_with_payload==0:
		print("NETWORK_SLEEPY_STONE_GUARDIAN DIAGNOSIS: World answers but no reply carried result.guardian -> Session does not deliver the result to the actor (Guardian.ACTIONS missing from CORRELATED_ACTIONS / _complete_shipping)")
	print("NETWORK_SLEEPY_STONE_GUARDIAN checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

# ------------------------------------------------- overridable by selfcheck --

func new_server_session():
	return Session.new()

func server_hosted()->void:
	pass

# ---------------------------------------------------------------- fixture --

func seed_fixture(adventure:=false)->bool:
	if folder.is_empty():
		folder=OS.get_environment("TEMP").path_join("sleepy-guardian-net-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
		if DirAccess.make_dir_recursive_absolute(folder)!=OK:return false
	save_path=folder.path_join("trial.json" if adventure else "world.json")
	var w:=World.new()
	w.save_path=save_path
	w.state["picnic"]=true
	if adventure:w.state["world_mode"]="adventure"
	w.state["mine_depths"]={"unlocked":5,"ready":{},"pumped":24,"hoist":false}
	w.switch_region(Guardian.REGION)
	var spot:=w.safe_arrival(SPOT_GUARDIAN if adventure else START)
	w.switch_region(Regions.HOME)
	if spot==Vector2.ZERO:return false
	for token:String in TOKENS:
		w.add_player(token,token.get_slice("-",2))
		var p:Dictionary=w.state.players[token]
		p["region"]=Guardian.REGION
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
	server=new_server_session()
	server_branch.add_child(server)
	for attempt in 8:
		var port:=randi_range(31000,58000)
		if server.host(port,"",save_path,KEY,"127.0.0.1",true,"websocket")==OK:
			server_hosted()
			return port
	return 0

func join(label:String,token:String,port:int)->Client:
	var c:=Client.new()
	c.label=label
	c.token=token
	c.needles=["\"notes\"","\"hz\"","\"phrase\""]+Guardian.BELL_NAMES+TOKENS
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

## Sends one action and collects this client's reply: the notice plus the guardian
## payload (whatever signal carries it).
func act(c:Client,action:String,cell:Vector2i)->Dictionary:
	var mark:=c.frames.size()
	c.session.perform(action,cell,"")
	var replied:=await wait_until(func():return not c.notices(mark).is_empty() or not c.payloads(mark).is_empty(),4.0)
	if not replied:return {"replied":false,"ok":false,"message":"","guardian":{},"payloads":0,"mark":mark}
	await wait_until(func():return not c.notices(mark).is_empty() and not c.payloads(mark).is_empty(),1.0)
	await settle([c])
	var notes:Array=c.notices(mark)
	var found:Array=c.payloads(mark)
	var message:String=str(notes[0].args[0]) if not notes.is_empty() else ""
	replies+=1
	if message.begins_with(UNWIRED_MESSAGE):replies_unwired+=1
	if not found.is_empty():replies_with_payload+=1
	else:print("NETWORK_SLEEPY_STONE_GUARDIAN INFO reply without a guardian payload: %s %s by %s -> %s"%[action,str(cell),c.label,message.left(40)])
	return {"replied":true,"ok":not notes.is_empty() and bool(notes[0].args[1]),"message":message,"guardian":found[0] if not found.is_empty() else {},"payloads":found.size(),"mark":mark}

func brief(reply:Dictionary)->String:
	return "{replied=%s ok=%s msg=%s payloads=%s guardian=%s}"%[str(reply.replied),str(reply.ok),str(reply.message).left(28),str(reply.payloads),str(reply.guardian)]

func outcome(reply:Dictionary)->String:
	return str(reply.guardian.get("outcome","<no guardian payload>"))

func stage(reply:Dictionary)->int:
	var value=reply.guardian.get("round",-1)
	return int(value) if (value is int or value is float) else -1

func walk(c:Client,points:Array,seconds:float=10.0)->bool:
	var index:=0
	var deadline:=Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<deadline and index<points.size():
		var last:bool=index==points.size()-1
		var delta:Vector2=points[index]-c.pos()
		if delta.length()<(0.25 if last else 0.4):
			index+=1
			continue
		c.session.input_direction(delta.limit_length() if last else delta.normalized())
		await create_timer(0.05).timeout
	c.session.input_direction(Vector2.ZERO)
	await pause(0.3)
	await settle([c])
	return index>=points.size()

## Walks along the middle row of the cave room (never across a bell or the statue).
func go(c:Client,target:Vector2)->bool:
	if c.pos().distance_to(target)<0.25:return true
	return await walk(c,[Vector2(c.pos().x,LANE_Y),Vector2(target.x,LANE_Y),target])

## Listens and returns the bell indices ([] when no usable hum came back).
func learn(c:Client,label:String)->Array:
	expect(await go(c,SPOT_GUARDIAN),"%s: %s walks in front of the statue"%[label,c.label])
	var heard:=await act(c,"guardian_listen",Guardian.GUARDIAN)
	expect(heard.replied and heard.ok and outcome(heard)=="listen" and heard.payloads==1,"%s: guardian_listen answered once with outcome listen (got %s)"%[label,brief(heard)])
	var bells:Array=[]
	var notes=heard.guardian.get("notes")
	if notes is Array:
		for note in notes:
			if not note is Dictionary or not note.has("bell") or not note.has("hz") or not note.has("shape") or not note.has("name"):return []
			var bell:=int(note.bell)
			if bell<0 or bell>=Guardian.BELLS.size():return []
			bells.append(bell)
	return bells

## Echoes the hum over the wire. Returns the last ring reply ({} if it stopped).
func solve_round(c:Client,label:String,expected_notes:int)->Dictionary:
	var bells:=await learn(c,label)
	expect(bells.size()==expected_notes,"%s: hum has %d notes (got %s)"%[label,expected_notes,str(bells)])
	if bells.size()!=expected_notes:return {}
	var last:={}
	for i in bells.size():
		expect(await go(c,SPOT_BELLS[bells[i]]),"%s: %s walks beside bell %d"%[label,c.label,bells[i]])
		last=await act(c,"guardian_ring",Guardian.BELLS[bells[i]])
		var final:bool=i==bells.size()-1
		expect(last.replied and last.ok and last.payloads==1 and int(last.guardian.get("bell",-1))==int(bells[i]),"%s: ring %d/%d accepted with one private reply (got %s)"%[label,i+1,bells.size(),brief(last)])
		if not final:expect(outcome(last)=="progress" and int(last.guardian.get("entered",-1))==i+1,"%s: note %d is progress (got %s)"%[label,i+1,brief(last)])
		if not last.ok:return {}
	return last

func record_is(value,want_round:int,want_calm:int,want_claimed:bool)->bool:
	return value is Dictionary and Guardian.valid(value) and int(value.round)==want_round and int(value.calm)==want_calm and value.claimed==want_claimed

func only_snapshots(c:Client,mark:int)->bool:
	var extra:=c.others(mark)
	for frame in extra:print("  unexpected frame to %s: %s %s"%[c.label,frame.name,str(frame.args).left(200)])
	return extra.is_empty()

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	expect(JSON.stringify({"k":Guardian.BELL_NAMES[0]}).contains(Guardian.BELL_NAMES[0]),"snapshot text search can see bell names")
	expect(seed_fixture(),"SEEDED FIXTURE written to TEMP and accepted by SaveSchema.validate")
	if save_path.is_empty() or not FileAccess.file_exists(save_path):return false
	var port:=start_server()
	expect(port>0,"server Session hosts on 127.0.0.1 with the websocket transport")
	if port==0:return false

	# ---- 1. solo: full solve + claim ------------------------------------
	solo=await join("solo",SOLO,port)
	expect(joined(solo),"solo joined over loopback")
	if not joined(solo):return false
	var ws:bool=server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and solo.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer
	expect(ws and server.multiplayer.is_server() and not solo.session.multiplayer.is_server() and solo.session.world==null,"real WebSocket server + remote client (client holds no World)")
	print("NETWORK_SLEEPY_STONE_GUARDIAN_LABEL machine=single process=single transport=%s loopback=127.0.0.1:%d fixture=SEEDED(unlocked=5,players placed in mine_4 cave) clock=real"%["websocket" if ws else "UNEXPECTED",port])
	expect(solo.region()==Guardian.REGION and solo.visible_ids()==[solo.session.own_id],"solo is alone on B4")
	expect(solo.sand()==0,"solo starts without crystal sand")
	var far:=await act(solo,"guardian_listen",Guardian.GUARDIAN)
	expect(far.replied and not far.ok and (far.guardian.get("notes",[]) as Array).is_empty(),"solo: listening from 3 tiles away is refused without notes (got %s)"%brief(far))
	expect(await go(solo,SPOT_GUARDIAN),"solo walks in front of the statue")
	var early:=await act(solo,"guardian_claim",Guardian.GUARDIAN)
	expect(early.replied and not early.ok and outcome(early)=="asleep" and solo.sand()==0,"solo: claim refused before the statue is awake (got %s)"%brief(early))
	var hum_before:=await learn(solo,"solo hum")
	await leave(solo)
	solo=await join("solo",SOLO,port)
	expect(joined(solo),"solo reconnects before solving")
	if not joined(solo):return false
	var hum_after:=await learn(solo,"solo hum after reconnect")
	expect(not hum_before.is_empty() and hum_before==hum_after,"solo hears the same hum after a reconnect (%s vs %s)"%[str(hum_before),str(hum_after)])
	if hum_before.is_empty():
		print("NETWORK_SLEEPY_STONE_GUARDIAN stopped after the solo listen: no usable hum came back")
		return false
	var first:=await solve_round(solo,"solo round 1",2)
	expect(outcome(first)=="round" and stage(first)==1,"solo: first phrase echoed (got %s)"%str(first.get("guardian")))
	var second:=await solve_round(solo,"solo round 2",3)
	expect(outcome(second)=="awake" and stage(second)==2,"solo: second phrase wakes the statue (got %s)"%str(second.get("guardian")))
	expect(await go(solo,SPOT_GUARDIAN),"solo walks back to the statue")
	var gift:=await act(solo,"guardian_claim",Guardian.GUARDIAN)
	expect(gift.ok and outcome(gift)=="claim" and gift.guardian.get("claimed")==true,"solo: claim accepted (got %s)"%brief(gift))
	expect(solo.sand()==Guardian.REWARD_COUNT,"solo: snapshot shows +%d crystal_sand (got %d)"%[Guardian.REWARD_COUNT,solo.sand()])
	var twice:=await act(solo,"guardian_claim",Guardian.GUARDIAN)
	expect(twice.replied and not twice.ok and outcome(twice)=="claimed" and solo.sand()==Guardian.REWARD_COUNT,"solo: second claim refused, still +%d (got %s)"%[Guardian.REWARD_COUNT,brief(twice)])
	expect(record_is(solo.own_view(),2,0,true),"solo: own snapshot shows the awake + claimed record (got %s)"%str(solo.own_view()))
	expect(solo.snapshot_hits.is_empty(),"solo: no snapshot ever carried hum notes or raw tokens %s"%str(solo.snapshot_hits.slice(0,3)))
	await leave(solo)

	# ---- 2. dual: privacy ------------------------------------------------
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	expect(joined(alpha) and joined(beta),"alpha and beta joined")
	if not joined(alpha) or not joined(beta):return false
	await settle([alpha,beta])
	var pair:=[alpha.session.own_id,beta.session.own_id]
	pair.sort()
	expect(alpha.visible_ids()==pair and beta.visible_ids()==pair and alpha.session.own_id!=beta.session.own_id,"both stand on B4 and see each other under distinct public ids")
	expect(alpha.session.own_id!=ALPHA and beta.session.own_id!=BETA,"public ids are not the profile tokens")
	expect(await go(alpha,SPOT_GUARDIAN) and await go(beta,SPOT_GUARDIAN),"both walk in front of the statue")
	# A listens; B must receive nothing but ordinary snapshots in the window.
	var beta_mark:=beta.frames.size()
	var beta_changes:=beta.changes
	var heard:=await act(alpha,"guardian_listen",Guardian.GUARDIAN)
	await pause(1.2)
	expect(heard.ok and outcome(heard)=="listen" and heard.payloads==1 and heard.guardian.get("notes") is Array and (heard.guardian.get("notes",[]) as Array).size()==2,"alpha's listen reply arrives exactly once on alpha's socket with 2 notes (got %s)"%brief(heard))
	expect(beta.changes>beta_changes,"beta kept receiving snapshots during alpha's listen window (%d)"%(beta.changes-beta_changes))
	expect(only_snapshots(beta,beta_mark),"beta received no notice / result frame for alpha's listen")
	expect(beta.payloads(beta_mark).is_empty(),"no guardian payload reached beta's socket")
	expect(beta.snapshot_hits.is_empty() and alpha.snapshot_hits.is_empty(),"no snapshot to either client carried notes: %s"%str((beta.snapshot_hits+alpha.snapshot_hits).slice(0,3)))
	# A solves both rounds while B stays idle.
	var a1:=await solve_round(alpha,"alpha round 1",2)
	expect(outcome(a1)=="round" and stage(a1)==1,"alpha: round 1 done (got %s)"%str(a1.get("guardian")))
	var a2:=await solve_round(alpha,"alpha round 2",3)
	expect(outcome(a2)=="awake" and stage(a2)==2,"alpha: statue awake (got %s)"%str(a2.get("guardian")))
	await pause(0.5)
	expect(only_snapshots(beta,beta_mark),"beta received only snapshots during alpha's whole solve (no ring results, no notices)")
	expect(beta.snapshot_hits.is_empty(),"beta's snapshots never carried alpha's notes: %s"%str(beta.snapshot_hits.slice(0,3)))
	var beta_own=beta.own_view()
	expect(beta_own==null or record_is(beta_own,0,0,false),"beta's own view is still asleep after alpha woke the statue (got %s)"%str(beta_own))
	expect(record_is(alpha.own_view(),2,0,false),"alpha's own snapshot shows the awake record (got %s)"%str(alpha.own_view()))
	var foreign:Dictionary=beta.session.snapshot.get("players",{}).get(alpha.session.own_id,{})
	expect(not foreign.has("inventory") and not foreign.has("receipts"),"beta's view of alpha has no inventory / receipts")
	print("NETWORK_SLEEPY_STONE_GUARDIAN INFO beta's view of alpha %s alpha's sleepy_guardian record"%("EXPOSES" if foreign.has("sleepy_guardian") else "does not expose"))
	# B's own statue is still asleep: B hears a 2-note hum; A gets nothing of it.
	var alpha_mark:=alpha.frames.size()
	var beta_heard:=await act(beta,"guardian_listen",Guardian.GUARDIAN)
	expect(beta_heard.ok and outcome(beta_heard)=="listen" and stage(beta_heard)==0 and (beta_heard.guardian.get("notes",[]) as Array).size()==2,"beta still hears the first 2-note hum (own record asleep) (got %s)"%brief(beta_heard))
	var beta_claim:=await act(beta,"guardian_claim",Guardian.GUARDIAN)
	expect(beta_claim.replied and not beta_claim.ok and outcome(beta_claim)=="asleep" and beta.sand()==0,"beta cannot claim on alpha's progress (got %s)"%brief(beta_claim))
	# Each claims exactly once. Beta uses the quiet route.
	expect(await go(alpha,SPOT_GUARDIAN),"alpha walks back to the statue")
	var alpha_claim:=await act(alpha,"guardian_claim",Guardian.GUARDIAN)
	expect(alpha_claim.ok and outcome(alpha_claim)=="claim" and alpha.sand()==Guardian.REWARD_COUNT,"alpha claims +%d crystal_sand (got %s, sand %d)"%[Guardian.REWARD_COUNT,brief(alpha_claim),alpha.sand()])
	await settle([beta])
	expect(beta.sand()==0,"alpha's claim gives beta nothing")
	# Transport replay of the same sequence is dropped; a fresh claim is refused.
	var replay_mark:=alpha.frames.size()
	alpha.session.request_action.rpc_id(1,alpha.session.counter,"guardian_claim",Guardian.GUARDIAN,"",alpha.region(),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha])
	expect(alpha.others(replay_mark).is_empty() and alpha.sand()==Guardian.REWARD_COUNT,"replayed claim sequence is dropped: no second reply, no second reward")
	var alpha_again:=await act(alpha,"guardian_claim",Guardian.GUARDIAN)
	expect(alpha_again.replied and not alpha_again.ok and outcome(alpha_again)=="claimed" and alpha.sand()==Guardian.REWARD_COUNT,"alpha's fresh second claim refused (got %s)"%brief(alpha_again))
	alpha_mark=alpha.frames.size()
	for visit in range(1,Guardian.CALM_NEEDED+1):
		var sat:=await act(beta,"guardian_sit",Guardian.GUARDIAN)
		expect(sat.ok and outcome(sat)==("awake" if visit==Guardian.CALM_NEEDED else "sit") and int(sat.guardian.get("calm",-1))==visit,"beta sit %d (got %s)"%[visit,brief(sat)])
	var beta_gift:=await act(beta,"guardian_claim",Guardian.GUARDIAN)
	expect(beta_gift.ok and outcome(beta_gift)=="claim" and beta.sand()==Guardian.REWARD_COUNT,"beta claims +%d via the quiet route (got %s)"%[Guardian.REWARD_COUNT,brief(beta_gift)])
	var beta_again:=await act(beta,"guardian_claim",Guardian.GUARDIAN)
	expect(beta_again.replied and not beta_again.ok and outcome(beta_again)=="claimed" and beta.sand()==Guardian.REWARD_COUNT,"beta's second claim refused (got %s)"%brief(beta_again))
	await settle([alpha])
	expect(only_snapshots(alpha,alpha_mark) and alpha.sand()==Guardian.REWARD_COUNT,"alpha received nothing but snapshots for beta's sits and claims, and keeps exactly +%d"%Guardian.REWARD_COUNT)
	expect(record_is(beta.own_view(),2,3,true) and record_is(alpha.own_view(),2,0,true),"own snapshots show each player's own finished record (%s / %s)"%[str(alpha.own_view()),str(beta.own_view())])

	# ---- 3. reconnect of alpha -------------------------------------------
	await leave(alpha)
	expect(await wait_until(func():return int(beta.session.snapshot.get("room_population",0))==1,4.0),"server sees alpha leave")
	alpha=await join("alpha",ALPHA,port)
	expect(joined(alpha),"alpha reconnects with the same token")
	if not joined(alpha):return false
	await settle([alpha])
	expect(alpha.sand()==Guardian.REWARD_COUNT and record_is(alpha.own_view(),2,0,true),"reconnected alpha sees the persisted record and reward (%s, sand %d)"%[str(alpha.own_view()),alpha.sand()])
	var after:=await act(alpha,"guardian_listen",Guardian.GUARDIAN)
	expect(after.replied and not after.ok and outcome(after)=="awake" and stage(after)==2 and after.guardian.get("claimed")==true,"reconnected alpha: statue is still awake and claimed (got %s)"%brief(after))
	var after_claim:=await act(alpha,"guardian_claim",Guardian.GUARDIAN)
	expect(after_claim.replied and not after_claim.ok and outcome(after_claim)=="claimed" and alpha.sand()==Guardian.REWARD_COUNT,"reconnected alpha cannot claim again (got %s)"%brief(after_claim))

	# ---- 4. server restart on the saved file ------------------------------
	expect(alpha.snapshot_hits.is_empty() and beta.snapshot_hits.is_empty(),"no snapshot in the whole session carried notes or raw tokens: %s"%str((alpha.snapshot_hits+beta.snapshot_hits).slice(0,3)))
	await leave(alpha)
	await leave(beta)
	expect(server.shutdown(),"server shuts down with a final save")
	await pause(0.2)
	server_branch.queue_free()
	var disk=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	expect(disk is Dictionary,"save file parses")
	if not disk is Dictionary:return false
	expect(Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"saved world passes SaveSchema")
	var wanted:={SOLO:[2,0,true],ALPHA:[2,0,true],BETA:[2,3,true]}
	for token:String in wanted:
		var person:Dictionary=disk.players.get(token,{})
		var saved=person.get("sleepy_guardian")
		expect(record_is(saved,wanted[token][0],wanted[token][1],wanted[token][2]) and saved.size()==3,"save holds %s's record %s (got %s)"%[token.get_slice("-",2),str(wanted[token]),str(saved)])
		expect(int(person.get("inventory",{}).get("crystal_sand",0))==Guardian.REWARD_COUNT,"save holds %s's +%d crystal_sand"%[token.get_slice("-",2),Guardian.REWARD_COUNT])
	var port2:=start_server()
	expect(port2>0,"a new server Session hosts the same save")
	if port2==0:return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	expect(joined(alpha) and joined(beta),"both rejoin the restarted server")
	if not joined(alpha) or not joined(beta):return false
	await settle([alpha,beta])
	expect(alpha.region()==Guardian.REGION and beta.region()==Guardian.REGION,"both are back on B4")
	expect(record_is(alpha.own_view(),2,0,true) and record_is(beta.own_view(),2,3,true),"records survive the restart (%s / %s)"%[str(alpha.own_view()),str(beta.own_view())])
	expect(alpha.sand()==Guardian.REWARD_COUNT and beta.sand()==Guardian.REWARD_COUNT,"rewards survive the restart")
	expect(await go(alpha,SPOT_GUARDIAN) and await go(beta,SPOT_GUARDIAN),"both stand at the statue after the restart")
	for c:Client in [alpha,beta]:
		var again:=await act(c,"guardian_listen",Guardian.GUARDIAN)
		expect(again.replied and not again.ok and outcome(again)=="awake" and stage(again)==2,"%s after restart: statue still awake (got %s)"%[c.label,brief(again)])
		var reclaim:=await act(c,"guardian_claim",Guardian.GUARDIAN)
		expect(reclaim.replied and not reclaim.ok and outcome(reclaim)=="claimed" and c.sand()==Guardian.REWARD_COUNT,"%s after restart: no second reward (got %s)"%[c.label,brief(reclaim)])
	expect(alpha.snapshot_hits.is_empty() and beta.snapshot_hits.is_empty(),"no snapshot after the restart carried notes or raw tokens")
	return await adventure_trial()

func adventure_trial()->bool:
	await leave(alpha)
	await leave(beta)
	expect(server.shutdown(),"The life room closes before the adventure fixture starts")
	server_branch.queue_free()
	await process_frame
	if not seed_fixture(true):return false
	var port:=start_server()
	if port==0:return false
	alpha=await join("alpha_trial",ALPHA,port)
	beta=await join("beta_trial",BETA,port)
	if not joined(alpha) or not joined(beta):return false
	var alpha_sand:=alpha.sand()
	var beta_sand:=beta.sand()
	expect(alpha.trial_view().is_empty() and beta.trial_view().is_empty(),"Both players enter B4 without a strike active")
	expect(await trial_act(alpha,Trial.START,true),"Alpha starts the adventure")
	expect(alpha.trial_phase()==Trial.Phase.WARNING and beta.trial_view().is_empty(),"Only Alpha gets the warning")
	expect(await walk(alpha,[Vector2(32.8,SPOT_GUARDIAN.y)]),"Alpha sidesteps on the actual cave floor")
	expect(await trial_act(beta,Trial.START,true),"Beta can start a separate round")
	expect(beta.trial_phase()==Trial.Phase.WARNING and beta.trial_view()!=alpha.trial_view(),"The two warning clocks are independent")
	expect(await wait_until(func():return alpha.trial_phase()==Trial.Phase.WARNING and alpha.trial_view().get("attack")==1,4.0),"Alpha gets the second warning")
	expect(await walk(alpha,[Vector2(32.8,13.40)]),"Alpha walks behind the second strike")
	expect(await wait_until(func():return beta.trial_phase()==Trial.Phase.MISSED,4.0),"Beta stays in the zone and misses")
	expect(await wait_until(func():return alpha.trial_phase()==Trial.Phase.SAFE,4.0),"Beta's miss leaves Alpha's progress intact")
	expect(await trial_act(beta,Trial.FINISH,false) and beta.own_view()==null and beta.sand()==beta_sand,"A miss cannot finish, grant currency or alter the save")
	expect(await go(alpha,SPOT_GUARDIAN),"Alpha walks back to the stone guardian")
	expect(await trial_act(alpha,Trial.FINISH,true) and record_is(alpha.own_view(),2,0,false),"Alpha earns the unclaimed gift")
	var remote:Dictionary=beta.session.snapshot.get("players",{}).get(alpha.session.own_id,{})
	expect(not remote.is_empty() and not remote.has(World.GUARDIAN_FIELD) and beta.own_view()==null,"Beta sees Alpha without personal puzzle progress")
	expect(alpha.snapshot_hits.is_empty() and beta.snapshot_hits.is_empty(),"The adventure reveals no profile tokens")
	await leave(alpha)
	await leave(beta)
	expect(server.shutdown(),"The host saves after the adventure")
	server_branch.queue_free()
	await process_frame
	port=start_server()
	if port==0:return false
	alpha=await join("alpha_trial_rejoin",ALPHA,port)
	beta=await join("beta_trial_rejoin",BETA,port)
	if not joined(alpha) or not joined(beta):return false
	expect(record_is(alpha.own_view(),2,0,false) and beta.own_view()==null and beta.trial_view().is_empty(),"Room reopen retains the earned gift and clears unfinished attempts")
	var claim:=await act(alpha,"guardian_claim",Guardian.GUARDIAN)
	expect(claim.ok and alpha.sand()==alpha_sand+Guardian.REWARD_COUNT and beta.sand()==beta_sand,"Only the successful player can claim the two crystal sand")
	var duplicate:=await act(alpha,"guardian_claim",Guardian.GUARDIAN)
	expect(duplicate.replied and not duplicate.ok and alpha.sand()==alpha_sand+Guardian.REWARD_COUNT,"Claim still pays exactly once")
	return true

func trial_act(client:Client,extra:String,accepted:bool)->bool:
	var mark:=client.frames.size()
	var sequence:int=client.session.perform(Trial.KEY,Guardian.GUARDIAN,extra)
	var replied:=await wait_until(func():return client.others(mark).any(func(frame):
		return frame.name=="action_completed" and frame.args[0]==sequence and frame.args[1]==Trial.KEY and frame.args[2].get("ok")==accepted
	),3.0)
	await settle([client])
	return replied

func teardown()->void:
	for c in [solo,alpha,beta]:
		if c!=null and is_instance_valid(c.session) and not c.session.shutting_down:
			c.session.shutdown()
	await pause(0.2)
	if server!=null and is_instance_valid(server) and server.world!=null:
		expect(server.shutdown(),"final server shutdown saves cleanly")
	await pause(0.2)
	for c in [solo,alpha,beta]:
		if c!=null and is_instance_valid(c.branch):c.branch.queue_free()
	if is_instance_valid(server_branch):server_branch.queue_free()
	await process_frame

func remove_folder()->bool:
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):return false
	var dir:=DirAccess.open(folder)
	if dir==null:return false
	for file in dir.get_files():
		if DirAccess.remove_absolute(folder.path_join(file))!=OK:return false
	return DirAccess.remove_absolute(folder)==OK and not DirAccess.dir_exists_absolute(folder)
