extends SceneTree
## 第 40 章金瓜石回訪「礦料調度」two-client Session acceptance over a real dedicated server
## and real WebSocket clients (modelled on test_lanyang_revisit_session.gd).
##
## LEVEL: one machine, ONE Godot process. A dedicated server Session listens on a free
## 127.0.0.1 port (websocket transport); two client Sessions (alpha, beta) and later a
## late joiner (gamma) join over loopback, each in its own branch with its own
## SceneMultiplayer. Clients only read their own received snapshots. The server World is
## never touched after seeding; the on-disk save is read (file only) after shutdowns.
##
## SEEDED FIXTURE (disclosed): built offline in a World before the server starts and
## validated with SaveSchema. EARNED there through World.act: the picnic (alpha), the
## Q07 hoist repair (alpha, mine_hoist_repair), alpha's and beta's first Bobo sorts
## (bobo_sort_start / answer ×3 / claim), beta's 4 copper_ore (borrow_mine_pick + one
## Jinguashi copper node). Written directly: board=true + soup/bread for the picnic,
## mine_depths unlocked 6 / pumped 24, hoist materials, gold_ore 3 per Bobo sort,
## alpha's gold_ore 2 + stone 6 for her two crates, the standing spots in Jinguashi
## (alpha 23.5,21.5 next to Bobo's table; beta 12.5,20.5 next to the shuttle), receipts
## cleared. No jinguashi_revisit key is preset. World time starts at 0 (day 1, spring)
## and only advances by the server's real-time ticks.
## Everything after the seed goes through client Sessions over the network; alpha walks
## (input_direction) from Bobo's table to the hoist and back, beta walks from the shuttle
## to Bobo's table.
## Replay: the raw request_action RPC re-sent with alpha's already-used sort sequence
## number but a different sort extra; Session drops it.
## NOT covered: multiple processes, TLS, latency/loss, crash durability (normal shutdowns
## only), season changes (rule level, test_jinguashi_revisit.gd).
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const JG=preload("res://scripts/jinguashi_revisit.gd")
const Mines=preload("res://scripts/mine_depths.gd")
const Bobo=preload("res://scripts/bobo_workshop.gd")
const KEY:="jinguashi-revisit-session"
const ALPHA:="jgrevisit-session-alpha-token"
const BETA:="jgrevisit-session-beta-token"
const GAMMA:="jgrevisit-session-gamma-token"
const KIT:="mine_lantern_kit"
const TABLE:=Vector2i(23,20)
const A_SPOT:=Vector2(23.5,21.5)
const B_SPOT:=Vector2(12.5,20.5)

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
		return session.snapshot.get("jinguashi_revisit",null)

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
	print("JINGUASHI_REVISIT_SESSION watchdog fired before completion")
	print("JINGUASHI_REVISIT_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("JINGUASHI_REVISIT_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("JINGUASHI_REVISIT_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("JINGUASHI_REVISIT_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

func seed_act(w:World,token:String,action:String,p:Vector2i,extra:String="")->bool:
	serial+=1
	return bool(w.act(token,"seed-%d"%serial,action,p,extra).ok)

func place(w:World,token:String,region:String,at:Vector2)->void:
	var p:Dictionary=w.state.players[token]
	p["region"]=region
	p["x"]=at.x
	p["y"]=at.y

func seed_bobo(w:World,token:String)->bool:
	w.state.players[token].inventory["gold_ore"]=int(w.state.players[token].inventory.get("gold_ore",0))+Bobo.INPUT
	place(w,token,"jinguashi",A_SPOT)
	if not seed_act(w,token,"bobo_sort_start",TABLE):return false
	for step in Bobo.STEPS.size():
		if not seed_act(w,token,"bobo_sort_answer",TABLE,"%d:%s"%[step,Bobo.STEPS[step]]):return false
	return seed_act(w,token,"bobo_sort_claim",TABLE)

func seed_world(path:String)->bool:
	var w:=World.new()
	w.add_player(ALPHA,"alpha")
	w.add_player(BETA,"beta")
	var a:Dictionary=w.state.players[ALPHA]
	var b:Dictionary=w.state.players[BETA]
	w.state["board"]=true
	a.inventory["soup"]=2
	a.inventory["bread"]=1
	place(w,ALPHA,"home",Vector2(40.5,30.5))
	if not seed_act(w,ALPHA,"picnic",Vector2i(40,29)):return false
	w.state["mine_depths"]={"unlocked":6,"ready":{},"pumped":24,"hoist":false}
	for item in Mines.HOIST_COST:a.inventory[item]=int(a.inventory.get(item,0))+int(Mines.HOIST_COST[item])
	place(w,ALPHA,"jinguashi",Vector2(27.5,19.5))
	if not seed_act(w,ALPHA,World.HOIST_ACTION,Mines.ENTRY):return false
	if not seed_bobo(w,ALPHA) or not seed_bobo(w,BETA):return false
	place(w,BETA,"home",Vector2(53.5,24.5))
	if not seed_act(w,BETA,"borrow_mine_pick",World.COPPER_CELL):return false
	place(w,BETA,"jinguashi",Vector2(27.5,20.5))
	if not seed_act(w,BETA,"pick",Vector2i(28,20)):return false
	if int(b.inventory.get("copper_ore",0))!=4:return false
	a.inventory["gold_ore"]=2
	a.inventory["stone"]=6
	place(w,ALPHA,"jinguashi",A_SPOT)
	place(w,BETA,"jinguashi",B_SPOT)
	for p:Dictionary in [a,b]:p["receipts"]={}
	w.active_tokens.clear()
	w.save_path=path
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.has(JG.STATE_KEY) or float(parsed.time)!=0.0:return false
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
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty() and c.session.snapshot.get("bobo_workshop") is Dictionary

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

## Walk with real movement input until `arrived` holds for the received position.
func walk(c:Client,direction:Vector2,arrived:Callable,seconds:float)->bool:
	var done:=await wait_until(func():
		c.session.input_direction(direction)
		return arrived.call(c.me()),seconds)
	for i in 6:
		c.session.input_direction(Vector2.ZERO)
		await process_frame
	await pause(0.5)
	await settle([c])
	return done

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
	expect(marks_of(everyone)==marks,"%s: bags and jinguashi_revisit unchanged in every watching snapshot"%label)

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
	return text({"crates":rec.get("crates"),"day":rec.get("day"),"sent":rec.get("sent"),"completed":rec.get("completed"),"done_day":rec.get("done_day")})

func row(crates:Dictionary,day:int,sent:Array,completed:bool,done_day:int)->String:
	return text({"crates":crates,"day":day,"sent":sent,"completed":completed,"done_day":done_day})

func read_disk()->Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(save_path))

func disk_valid(disk:Variant)->bool:
	return disk is Dictionary and Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("jinguashi-revisit-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"SEEDED FIXTURE (picnic, hoist, two Bobo sorts, beta's copper earned offline; ores/spots written; no jinguashi_revisit) accepted by SaveSchema"):return false
	var probe:=World.new()
	if not expect(probe.load_world(save_path),"probe: seeded save loads"):return false
	probe.switch_region("jinguashi")
	expect(probe.can_stand(A_SPOT) and probe.can_stand(B_SPOT) and probe.can_stand(Vector2(26.5,21.5)) and probe.can_stand(Vector2(21.5,20.5)),"probe: both spots and both walk targets are standable")
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
	print("JINGUASHI_REVISIT_SESSION_LABEL machine=single process=single transport=websocket loopback=127.0.0.1:%d clients=2(+late joiner) fixture=SEEDED(picnic,hoist,bobo sorts,copper earned offline; ores,spots) shutdown=normal-only"%port)

	# 1. Fresh: unlocked, both ready, no record, spring order.
	var spring:={"bobo":"gold_ore","ferry":"copper_ore","depot":"stone"}
	for c:Client in [alpha,beta]:
		var snap:Dictionary=c.session.snapshot
		expect(c.revisit()==null and JG.unlocked(snap) and JG.player_ready(snap) and JG.sort_block(snap)=="","case 1 %s: unlocked, ready, no record yet"%c.label)
		expect(JG.today(snap)==1 and JG.order_season(snap)=="spring" and JG.order(snap)==spring,"case 1 %s: day 1 spring order"%c.label)
		expect(JG.sort_cell(snap)==TABLE and JG.dest_cell(snap,"bobo")==TABLE,"case 1 %s: Bobo's table read from the client snapshot"%c.label)
		private_check(c,[beta if c==alpha else alpha],"case 1")

	# 2. Refusals leave both ends unchanged.
	await refuse(alpha,JG.SHIP_ACTION,TABLE,"",JG.UNSORTED%"波波的整理桌","case 2 ship before any sort",[beta])
	await refuse(alpha,JG.SORT_ACTION,TABLE,"bobo:wood",JG.BAD_SORT,"case 2 malformed sort",[beta])
	await refuse(beta,JG.SORT_ACTION,TABLE,"bobo:gold_ore",JG.TOO_FAR,"case 2 beta too far from Bobo's table",[alpha])
	await refuse(alpha,JG.CLAIM_ACTION,TABLE,"",JG.NOT_DONE,"case 2 claim before completion",[beta])

	# 3. Alpha sorts the shared crates; both see them.
	var first:=await succeed(alpha,JG.SORT_ACTION,TABLE,"bobo:gold_ore","case 3 alpha sorts Bobo's crate",[beta])
	await wait_until(func():return beta.revisit() is Dictionary,3.0)
	for c:Client in [alpha,beta]:
		expect(public_row(c)==row({"bobo":"gold_ore","ferry":"","depot":""},0,[],false,0),"case 3 %s sees Bobo's crate sorted (%s)"%[c.label,public_row(c)])
	await succeed(alpha,JG.SORT_ACTION,TABLE,"ferry:copper_ore","case 3 alpha sorts the ferry crate",[beta])
	await succeed(alpha,JG.SORT_ACTION,TABLE,"depot:stone","case 3 alpha sorts the depot crate",[beta])
	await wait_until(func():return public_row(beta).contains("stone"),3.0)
	for c:Client in [alpha,beta]:
		expect(JG.rows(c.session.snapshot).all(func(r):return r.ok),"case 3 %s: all crates match the order"%c.label)

	# 4. Replay of a used sequence is dropped.
	await settle([alpha,beta])
	var counts:=[alpha.notices.size(),beta.notices.size()]
	var before4:=marks_of([alpha,beta])
	alpha.session.request_action.rpc_id(1,int(first.sequence),JG.SORT_ACTION,TABLE,"bobo:stone",str(alpha.session.snapshot.get("region_id","")),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==counts[0] and beta.notices.size()==counts[1],"case 4 re-sent sequence %d gets no notice"%int(first.sequence))
	expect(marks_of([alpha,beta])==before4,"case 4 re-sent sequence changes nothing on either end")

	# 5. Split shipping; completion seen by both.
	await succeed(alpha,JG.SHIP_ACTION,TABLE,"","case 5 alpha ships Bobo's crate",[beta])
	expect(int(alpha.bag().get("gold_ore",0))==0,"case 5 alpha's 2 gold_ore taken")
	await refuse(alpha,JG.SORT_ACTION,TABLE,"bobo:copper_ore",JG.SENT_LOCKED,"case 5 re-sort after a send",[beta])
	await succeed(beta,JG.SHIP_ACTION,JG.SHUTTLE,"","case 5 beta ships the ferry crate at the shuttle",[alpha])
	expect(int(beta.bag().get("copper_ore",0))==0,"case 5 beta's 4 copper_ore taken")
	await refuse(beta,JG.SHIP_ACTION,JG.SHUTTLE,"",JG.ALREADY_SENT%"渡口家園工坊","case 5 ferry crate twice",[alpha])
	await refuse(alpha,JG.SHIP_ACTION,JG.HOIST,"",JG.TOO_FAR,"case 5 alpha still at Bobo's table",[beta])
	expect(await walk(alpha,Vector2.RIGHT,func(me):return float(me.get("x",0.0))>=26.5,8.0),"case 5 alpha walks toward the hoist (x=%s)"%str(alpha.me().get("x")))
	var done:=await succeed(alpha,JG.SHIP_ACTION,JG.HOIST,"","case 5 alpha ships the depot crate by the hoist",[beta])
	expect(str(done.message)==JG.COMPLETE_OK,"case 5 completion message")
	await wait_until(func():return JG.completed(alpha.session.snapshot) and JG.completed(beta.session.snapshot),3.0)
	for c:Client in [alpha,beta]:
		expect(public_row(c)==row(spring,1,["bobo","ferry","depot"],true,1),"case 5 %s sees the completed record (%s)"%[c.label,public_row(c)])
	await refuse(beta,JG.SHIP_ACTION,JG.SHUTTLE,"",JG.ALREADY_DONE,"case 5 ship after completion",[alpha])

	# 6. Claims once each; the claim set stays private.
	await refuse(beta,JG.CLAIM_ACTION,TABLE,"",JG.TOO_FAR,"case 6 beta still at the shuttle",[alpha])
	expect(await walk(beta,Vector2.RIGHT,func(me):return float(me.get("x",0.0))>=21.0,12.0),"case 6 beta walks to Bobo's table (x=%s)"%str(beta.me().get("x")))
	await succeed(beta,JG.CLAIM_ACTION,TABLE,"","case 6 beta claims",[alpha])
	expect(int(beta.bag().get(KIT,0))==1 and beta.revisit().get("claimed_own")==true,"case 6 beta holds one kit and sees her own claim")
	expect(alpha.revisit().get("claimed_own")==false and int(alpha.bag().get(KIT,0))==0,"case 6 alpha does not see beta's claim as hers")
	for c:Client in [alpha,beta]:private_check(c,[beta if c==alpha else alpha],"case 6")
	await refuse(beta,JG.CLAIM_ACTION,TABLE,"",JG.CLAIMED,"case 6 beta claims twice",[alpha])
	expect(await walk(alpha,Vector2.LEFT,func(me):return float(me.get("x",99.0))<=24.5,8.0),"case 6 alpha walks back to Bobo's table (x=%s)"%str(alpha.me().get("x")))
	await succeed(alpha,JG.CLAIM_ACTION,TABLE,"","case 6 alpha claims",[beta])
	expect(int(alpha.bag().get(KIT,0))==1 and alpha.revisit().get("claimed_own")==true,"case 6 alpha holds one kit")
	await refuse(alpha,JG.CLAIM_ACTION,TABLE,"",JG.CLAIMED,"case 6 alpha claims twice",[beta])

	# 7. Reconnect cannot re-claim.
	await leave(beta)
	beta=null
	await pause(0.3)
	beta=await join("beta",BETA,port)
	if not expect(joined(beta),"case 7 beta reconnects"):return false
	await settle([alpha,beta])
	expect(beta.revisit().get("claimed_own")==true and int(beta.bag().get(KIT,0))==1,"case 7 reconnected beta sees her own claim and kit")
	await refuse(beta,JG.CLAIM_ACTION,TABLE,"",JG.CLAIMED,"case 7 reconnected beta cannot re-claim",[alpha])

	# 8. Normal shutdown → exact save.
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 8 server shuts down with a final save")
	var disk=read_disk()
	if not expect(disk is Dictionary,"case 8 save parses"):return false
	expect(disk_valid(disk),"case 8 saved world passes SaveSchema")
	var rec=disk.get(JG.STATE_KEY,{})
	expect(rec is Dictionary and rec.size()==6,"case 8 save: record has exactly six fields")
	expect(text(rec.get("crates"))==text(spring) and int(rec.get("day",-1))==1 and text(rec.get("sent"))==text(["bobo","ferry","depot"]) and rec.get("completed")==true and int(rec.get("done_day",-1))==1,"case 8 save: crates/day/sent/completed/done_day")
	var claimers:Array=rec.get("claimed",{}).keys()
	claimers.sort()
	var want:=[ALPHA,BETA]
	want.sort()
	expect(claimers==want and rec.claimed.values().all(func(v):return v==true),"case 8 save: exactly alpha and beta claimed")
	var da:Dictionary=disk.players[ALPHA].inventory
	var db:Dictionary=disk.players[BETA].inventory
	expect(int(da.get(KIT,0))==1 and int(db.get(KIT,0))==1,"case 8 save: one kit each")
	expect(int(da.get("gold_ore",0))==0 and int(da.get("stone",0))==0 and int(db.get("copper_ore",0))==0,"case 8 save: the shipped ores are gone")

	# 9. Restart; late joiner sees completion.
	var port2:=start_server()
	if not expect(port2>0,"case 9 restarted server hosts the same save"):return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	if not expect(joined(alpha) and joined(beta),"case 9 both rejoin"):return false
	await settle([alpha,beta])
	for c:Client in [alpha,beta]:
		expect(public_row(c)==row(spring,1,["bobo","ferry","depot"],true,1) and c.revisit().get("claimed_own")==true,"case 9 %s: restart consistent"%c.label)
	gamma=await join("gamma",GAMMA,port2)
	if not expect(joined(gamma),"case 9 late joiner gamma joins"):return false
	await settle([alpha,beta,gamma])
	expect(JG.completed(gamma.session.snapshot) and gamma.revisit().get("claimed_own")==false,"case 9 gamma sees the completed revisit, own flag false")
	expect(JG.claim_block(gamma.session.snapshot,gamma.bag())==JG.NOT_READY,"case 9 gamma's client helper: sort with Bobo first")
	private_check(gamma,[alpha,beta],"case 9")
	await refuse(gamma,JG.CLAIM_ACTION,TABLE,"",JG.WRONG_REGION,"case 9 gamma (at home) cannot claim",[alpha,beta])
	await leave(gamma)
	gamma=null
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 9 restarted server shuts down cleanly")
	var after=read_disk()
	expect(disk_valid(after) and text(after.get(JG.STATE_KEY))==text(disk.get(JG.STATE_KEY)) and after.players.has(GAMMA),"case 9 final save valid, record unchanged, gamma recorded")
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
