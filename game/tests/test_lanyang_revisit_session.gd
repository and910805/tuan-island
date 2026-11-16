extends SceneTree
## 第 40 章蘭陽回訪「旱日分流」two-client Session acceptance over a real dedicated server and
## real WebSocket clients (modelled on test_table_warmer_session.gd).
##
## LEVEL: one machine, ONE Godot process. A dedicated server Session listens on a free
## 127.0.0.1 port (websocket transport); two client Sessions (alpha, beta) and later a
## late joiner (gamma) join over loopback, each in its own branch with its own
## SceneMultiplayer. Clients only read their own received snapshots. The server World is
## never touched after seeding; the on-disk save is read (file only) after shutdowns.
##
## SEEDED FIXTURE (disclosed): built offline in a World before the server starts and
## validated with SaveSchema. EARNED there through World.act: the canal repair (alpha:
## lanyang_clear ×3, lanyang_donate), alpha's and beta's first 分水 memories
## (memory_observe ×3, memory_gate/memory_flow ×3) and the plaque (alpha). Written
## directly: repair materials, the standing spots in Lanyang (alpha 32.5,24.5 next to the
## junction and the upstream field; beta 32.5,30.5 next to Xinghe, the middle and the tail
## field), receipts cleared. No lanyang_revisit key is preset. World time starts at 0
## (day 1, spring, dry) and only advances by the server's real-time ticks.
## Everything after the seed goes through client Sessions over the network; alpha walks
## (input_direction) from the junction to Xinghe before claiming.
## Replay: the raw request_action RPC re-sent with alpha's already-used gate sequence
## number but a different gate extra; Session drops it.
## NOT covered: multiple processes, TLS, latency/loss, crash durability (normal shutdowns
## only), rainy-day / season rules (rule level, test_lanyang_revisit.gd).
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Memory=preload("res://scripts/history_memory.gd")
const KEY:="lanyang-revisit-session"
const ALPHA:="revisit-session-alpha-token"
const BETA:="revisit-session-beta-token"
const GAMMA:="revisit-session-gamma-token"
const KIT:="water_share_plaque_kit"
const A_SPOT:=Vector2(32.5,24.5)
const B_SPOT:=Vector2(32.5,30.5)

class Client:
	var label:=""
	var token:=""
	var branch:Node
	var session
	var notices:Array=[]
	var changes:=0
	func on_notice(message:String,success:bool)->void:
		notices.append([message,success])
	func on_changed(_data:Dictionary,_id:String)->void:
		changes+=1
	func me()->Dictionary:
		var people=session.snapshot.get("players",{})
		if not people is Dictionary or session.own_id.is_empty():return {}
		return people.get(session.own_id,{})
	func bag()->Dictionary:
		var inv=me().get("inventory",{})
		return inv if inv is Dictionary else {}
	func revisit()->Variant:
		return session.snapshot.get("lanyang_revisit",null)

var checks:=0
var failures:=0
var serial:=0
var folder:=""
var save_path:=""
var server
var server_branch:Node
var finished:=false
var alpha:Client
var beta:Client
var gamma:Client

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)
	return ok

func _initialize()->void:
	create_timer(110.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("LANYANG_REVISIT_SESSION watchdog fired before completion")
	print("LANYANG_REVISIT_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("LANYANG_REVISIT_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("LANYANG_REVISIT_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("LANYANG_REVISIT_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

func seed_act(w:World,token:String,action:String,p:Vector2i,extra:String="")->bool:
	serial+=1
	return bool(w.act(token,"seed-%d"%serial,action,p,extra).ok)

func stand(w:World,token:String,cell:Vector2i)->void:
	var p:Dictionary=w.state.players[token]
	p["region"]="lanyang"
	p["x"]=cell.x-0.5
	p["y"]=cell.y+0.5

func seed_memory(w:World,token:String)->bool:
	for cell:Vector2i in Memory.OBSERVATIONS:
		stand(w,token,cell)
		if not seed_act(w,token,"memory_observe",cell):return false
	stand(w,token,Memory.SERVICE)
	for pair in [[2,2],[1,3],[2,1]]:
		if not seed_act(w,token,"memory_gate",Memory.SERVICE,"a:%d"%pair[0]):return false
		if not seed_act(w,token,"memory_gate",Memory.SERVICE,"b:%d"%pair[1]):return false
		if not seed_act(w,token,"memory_flow",Memory.SERVICE):return false
	return true

func seed_world(path:String)->bool:
	var w:=World.new()
	w.add_player(ALPHA,"alpha")
	w.add_player(BETA,"beta")
	for cell:Vector2i in World.LANYANG_LIFE.BLOCKAGES:
		stand(w,ALPHA,cell)
		if not seed_act(w,ALPHA,"lanyang_clear",cell):return false
	stand(w,ALPHA,World.LANYANG_LIFE.SERVICE)
	for item in World.LANYANG_LIFE.REPAIR_COST:w.state.players[ALPHA].inventory[item]=int(World.LANYANG_LIFE.REPAIR_COST[item])
	if not seed_act(w,ALPHA,"lanyang_donate",World.LANYANG_LIFE.SERVICE):return false
	if not seed_memory(w,ALPHA) or not seed_memory(w,BETA):return false
	stand(w,ALPHA,Memory.SERVICE)
	if not seed_act(w,ALPHA,"memory_plaque",Memory.SERVICE):return false
	var a:Dictionary=w.state.players[ALPHA]
	var b:Dictionary=w.state.players[BETA]
	a["x"]=A_SPOT.x
	a["y"]=A_SPOT.y
	b["x"]=B_SPOT.x
	b["y"]=B_SPOT.y
	for p:Dictionary in [a,b]:p["receipts"]={}
	w.active_tokens.clear()
	w.save_path=path
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.has(Revisit.STATE_KEY) or float(parsed.time)!=0.0:return false
	return Schema.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

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
	var ok:bool=server.shutdown()
	await pause(0.2)
	server_branch.queue_free()
	await process_frame
	return ok

func join(label:String,token:String,port:int)->Client:
	var c:=Client.new()
	c.label=label
	c.token=token
	c.branch=new_branch("Client_%s_"%label)
	c.session=Session.new()
	c.branch.add_child(c.session)
	c.session.profile["token"]=token
	c.session.notice.connect(c.on_notice)
	c.session.changed.connect(c.on_changed)
	if c.session.join("ws://127.0.0.1:%d"%port,port,label,KEY)!=OK:return c
	await wait_until(func():return joined(c),8.0)
	return c

func joined(c:Client)->bool:
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty() and c.session.snapshot.get("history_memory") is Dictionary

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
	await create_timer(seconds,true,false,true).timeout

func settle(clients:Array)->void:
	var marks:Array=clients.map(func(c):return c.changes)
	await wait_until(func():
		for i in clients.size():
			if clients[i].changes<int(marks[i])+2:return false
		return true,3.0)

func act(c:Client,action:String,p:Vector2i,extra:String="")->Dictionary:
	var before:=c.notices.size()
	var sequence:int=c.session.perform(action,p,extra)
	var replied:=await wait_until(func():return c.notices.size()>before,4.0)
	if not replied:return {"replied":false,"ok":false,"message":"","sequence":sequence}
	await settle([c])
	var reply:Array=c.notices[before]
	return {"replied":true,"ok":bool(reply[1]),"message":str(reply[0]),"sequence":sequence}

## Walk with real movement input until the received y reaches `target_y`.
func walk_down(c:Client,target_y:float)->bool:
	var arrived:=await wait_until(func():
		c.session.input_direction(Vector2.DOWN)
		return float(c.me().get("y",0.0))>=target_y,8.0)
	for i in 6:
		c.session.input_direction(Vector2.ZERO)
		await process_frame
	await pause(0.5)
	await settle([c])
	return arrived

# ---------------------------------------------------------------- helpers --

static func canon(d:Variant)->Dictionary:
	var out:={}
	if not d is Dictionary:return {"<invalid>":-1}
	for item in d:
		if int(d[item])!=0:out[str(item)]=int(d[item])
	return out

static func text(d:Variant)->String:
	return JSON.stringify(d,"",true)

func marks_of(clients:Array)->Array:
	return clients.map(func(x):return [text(canon(x.bag())),text(x.revisit())])

func refuse(c:Client,action:String,p:Vector2i,extra:String,message:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var marks:=marks_of(everyone)
	var r:=await act(c,action,p,extra)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	expect(marks_of(everyone)==marks,"%s: bags and lanyang_revisit unchanged in every watching snapshot"%label)

func succeed(c:Client,action:String,p:Vector2i,extra:String,label:String,watchers:Array)->Dictionary:
	var r:=await act(c,action,p,extra)
	expect(r.replied and r.ok,"%s: ok (got ok=%s '%s')"%[label,str(r.ok),str(r.message)])
	await settle([c]+watchers)
	return r

func private_check(c:Client,others:Array,label:String)->void:
	var dump:=JSON.stringify(c.session.snapshot)
	var leaked:=false
	for o:Client in others+[c]:
		if dump.contains(o.token):leaked=true
	expect(not leaked,"%s: %s's snapshot contains no raw token"%[label,c.label])
	var rec=c.revisit()
	expect(rec==null or (rec is Dictionary and not rec.has("claimed")),"%s: %s's snapshot carries no claim set"%[label,c.label])

func public_row(c:Client)->String:
	var rec=c.revisit()
	if not rec is Dictionary:return "null"
	return text({"gates":rec.get("gates"),"day":rec.get("day"),"checked":rec.get("checked"),"completed":rec.get("completed")})

func read_disk()->Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(save_path))

func disk_valid(disk:Variant)->bool:
	return disk is Dictionary and Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("lanyang-revisit-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"SEEDED FIXTURE (repair, two memories, plaque earned offline; spots written; no lanyang_revisit) accepted by SaveSchema"):return false
	var probe:=World.new()
	if not expect(probe.load_world(save_path),"probe: seeded save loads"):return false
	probe.switch_region("lanyang")
	expect(probe.can_stand(A_SPOT) and probe.can_stand(B_SPOT) and probe.can_stand(Vector2(32.5,28.5)),"probe: both spots and alpha's claim spot are standable")
	probe.switch_region("home")
	probe=null
	var port:=start_server()
	if not expect(port>0,"server Session hosts on 127.0.0.1 (websocket)"):return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	if not expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback"):return false
	expect(server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer,"server and clients use WebSocketMultiplayerPeer")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World")
	await settle([alpha,beta])
	print("LANYANG_REVISIT_SESSION_LABEL machine=single process=single transport=websocket loopback=127.0.0.1:%d clients=2(+late joiner) fixture=SEEDED(repair,memories,plaque earned offline; spots) shutdown=normal-only"%port)

	# 1. Fresh: unlocked, both ready, no record.
	for c:Client in [alpha,beta]:
		var snap:Dictionary=c.session.snapshot
		expect(c.revisit()==null and Revisit.unlocked(snap) and Revisit.player_ready(snap) and Revisit.gate_block(snap)=="","case 1 %s: unlocked, ready, no record yet"%c.label)
		expect(Revisit.today(snap)==1 and Revisit.season(snap)=="spring" and Revisit.demand(snap)==[6,4,2],"case 1 %s: day 1 spring demand 6/4/2"%c.label)
		private_check(c,[beta if c==alpha else alpha],"case 1")

	# 2. Refusals leave both ends unchanged.
	await refuse(alpha,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS.upstream,"",Revisit.NO_GATES_TODAY,"case 2 check before any gate",[beta])
	await refuse(alpha,Revisit.GATE_ACTION,Revisit.GATE_CELL,"a:9",Revisit.BAD_GATE,"case 2 malformed gate",[beta])
	await refuse(beta,Revisit.GATE_ACTION,Revisit.GATE_CELL,"a:3",Revisit.TOO_FAR,"case 2 beta too far from the junction",[alpha])
	await refuse(beta,Revisit.CLAIM_ACTION,Revisit.SERVICE,"",Revisit.NOT_DONE,"case 2 claim before completion",[alpha])

	# 3. Alpha sets the shared gates; both see them.
	var first:=await succeed(alpha,Revisit.GATE_ACTION,Revisit.GATE_CELL,"a:3","case 3 alpha sets the upstream gate",[beta])
	await wait_until(func():return beta.revisit() is Dictionary,3.0)
	for c:Client in [alpha,beta]:
		expect(public_row(c)==text({"gates":[3,0],"day":1,"checked":[],"completed":false}),"case 3 %s sees gates [3,0] day 1 (%s)"%[c.label,public_row(c)])
	await succeed(alpha,Revisit.GATE_ACTION,Revisit.GATE_CELL,"b:2","case 3 alpha sets the middle gate",[beta])
	await wait_until(func():return public_row(beta).contains("2"),3.0)
	for c:Client in [alpha,beta]:
		expect(Revisit.shares(c.session.snapshot)==[6,4,2],"case 3 %s computes the 6/4/2 split"%c.label)

	# 4. Replay of a used sequence is dropped.
	await settle([alpha,beta])
	var counts:=[alpha.notices.size(),beta.notices.size()]
	var before4:=marks_of([alpha,beta])
	alpha.session.request_action.rpc_id(1,int(first.sequence),Revisit.GATE_ACTION,Revisit.GATE_CELL,"b:3",str(alpha.session.snapshot.get("region_id","")),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==counts[0] and beta.notices.size()==counts[1],"case 4 re-sent sequence %d gets no notice"%int(first.sequence))
	expect(marks_of([alpha,beta])==before4,"case 4 re-sent sequence changes nothing on either end")

	# 5. Split checks; completion seen by both.
	await succeed(alpha,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS.upstream,"","case 5 alpha checks upstream",[beta])
	await refuse(alpha,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS.upstream,"",Revisit.ALREADY_CHECKED,"case 5 upstream twice",[beta])
	await succeed(beta,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS.middle,"","case 5 beta checks the middle field",[alpha])
	var done:=await succeed(beta,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS.tail,"","case 5 beta checks the tail field",[alpha])
	expect(str(done.message)==Revisit.COMPLETE_OK,"case 5 completion message")
	await wait_until(func():return Revisit.completed(alpha.session.snapshot) and Revisit.completed(beta.session.snapshot),3.0)
	for c:Client in [alpha,beta]:
		expect(public_row(c)==text({"gates":[3,2],"day":1,"checked":["upstream","middle","tail"],"completed":true}),"case 5 %s sees the completed record (%s)"%[c.label,public_row(c)])
		expect(Revisit.tech_unlocked(c.session.snapshot),"case 5 %s: diversion gate tech unlocked"%c.label)
	await refuse(alpha,Revisit.GATE_ACTION,Revisit.GATE_CELL,"a:1",Revisit.ALREADY_DONE,"case 5 gate after completion",[beta])

	# 6. Claims once each; the claim set stays private.
	await succeed(beta,Revisit.CLAIM_ACTION,Revisit.SERVICE,"","case 6 beta claims",[alpha])
	expect(int(beta.bag().get(KIT,0))==1 and beta.revisit().get("claimed_own")==true,"case 6 beta holds one kit and sees her own claim")
	expect(alpha.revisit().get("claimed_own")==false and int(alpha.bag().get(KIT,0))==0,"case 6 alpha does not see beta's claim as hers")
	for c:Client in [alpha,beta]:private_check(c,[beta if c==alpha else alpha],"case 6")
	await refuse(beta,Revisit.CLAIM_ACTION,Revisit.SERVICE,"",Revisit.CLAIMED,"case 6 beta claims twice",[alpha])
	await refuse(alpha,Revisit.CLAIM_ACTION,Revisit.SERVICE,"",Revisit.TOO_FAR,"case 6 alpha still at the junction",[beta])
	expect(await walk_down(alpha,28.3),"case 6 alpha walks toward Xinghe (y=%s)"%str(alpha.me().get("y")))
	await succeed(alpha,Revisit.CLAIM_ACTION,Revisit.SERVICE,"","case 6 alpha claims",[beta])
	expect(int(alpha.bag().get(KIT,0))==1 and alpha.revisit().get("claimed_own")==true,"case 6 alpha holds one kit")
	await refuse(alpha,Revisit.CLAIM_ACTION,Revisit.SERVICE,"",Revisit.CLAIMED,"case 6 alpha claims twice",[beta])

	# 7. Reconnect cannot re-claim.
	await leave(beta)
	beta=null
	await pause(0.3)
	beta=await join("beta",BETA,port)
	if not expect(joined(beta),"case 7 beta reconnects"):return false
	await settle([alpha,beta])
	expect(beta.revisit().get("claimed_own")==true and int(beta.bag().get(KIT,0))==1,"case 7 reconnected beta sees her own claim and kit")
	await refuse(beta,Revisit.CLAIM_ACTION,Revisit.SERVICE,"",Revisit.CLAIMED,"case 7 reconnected beta cannot re-claim",[alpha])

	# 8. Normal shutdown → exact save.
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 8 server shuts down with a final save")
	var disk=read_disk()
	if not expect(disk is Dictionary,"case 8 save parses"):return false
	expect(disk_valid(disk),"case 8 saved world passes SaveSchema")
	var rec=disk.get(Revisit.STATE_KEY,{})
	expect(rec is Dictionary and rec.size()==5,"case 8 save: record has exactly five fields")
	var disk_gates=rec.get("gates",[])
	expect(disk_gates is Array and disk_gates.size()==2 and int(disk_gates[0])==3 and int(disk_gates[1])==2 and int(rec.get("day",-1))==1 and text(rec.get("checked"))==text(["upstream","middle","tail"]) and rec.get("completed")==true,"case 8 save: gates/day/checked/completed")
	var claimers:Array=rec.get("claimed",{}).keys()
	claimers.sort()
	var want:=[ALPHA,BETA]
	want.sort()
	expect(claimers==want and rec.claimed.values().all(func(v):return v==true),"case 8 save: exactly alpha and beta claimed")
	expect(int(disk.players[ALPHA].inventory.get(KIT,0))==1 and int(disk.players[BETA].inventory.get(KIT,0))==1,"case 8 save: one kit each")

	# 9. Restart; late joiner sees completion.
	var port2:=start_server()
	if not expect(port2>0,"case 9 restarted server hosts the same save"):return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	if not expect(joined(alpha) and joined(beta),"case 9 both rejoin"):return false
	await settle([alpha,beta])
	for c:Client in [alpha,beta]:
		expect(public_row(c)==text({"gates":[3,2],"day":1,"checked":["upstream","middle","tail"],"completed":true}) and c.revisit().get("claimed_own")==true,"case 9 %s: restart consistent"%c.label)
	gamma=await join("gamma",GAMMA,port2)
	if not expect(joined(gamma),"case 9 late joiner gamma joins"):return false
	await settle([alpha,beta,gamma])
	expect(Revisit.completed(gamma.session.snapshot) and gamma.revisit().get("claimed_own")==false,"case 9 gamma sees the completed revisit, own flag false")
	expect(Revisit.claim_block(gamma.session.snapshot,gamma.bag())==Revisit.NOT_READY,"case 9 gamma's client helper: finish own first memory first")
	private_check(gamma,[alpha,beta],"case 9")
	await refuse(gamma,Revisit.CLAIM_ACTION,Revisit.SERVICE,"",Revisit.WRONG_REGION,"case 9 gamma (at home) cannot claim",[alpha,beta])
	await leave(gamma)
	gamma=null
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 9 restarted server shuts down cleanly")
	var after=read_disk()
	expect(disk_valid(after) and text(after.get(Revisit.STATE_KEY))==text(disk.get(Revisit.STATE_KEY)) and after.players.has(GAMMA),"case 9 final save valid, record unchanged, gamma recorded")
	return true

func teardown()->void:
	for c in [alpha,beta,gamma]:
		if c!=null and is_instance_valid(c.session) and not c.session.shutting_down:
			c.session.shutdown()
	await pause(0.2)
	if server!=null and is_instance_valid(server) and server.world!=null:
		expect(server.shutdown(),"final server shutdown saves cleanly")
	await pause(0.2)
	for c in [alpha,beta,gamma]:
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
