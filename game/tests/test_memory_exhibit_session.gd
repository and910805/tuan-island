extends SceneTree
## 第 40 章風鈴節廣場「地方記憶展」two-client Session acceptance over a real dedicated
## server and real WebSocket clients (modelled on test_lanyang_revisit_session.gd).
##
## LEVEL: one machine, ONE Godot process. A dedicated server Session listens on a free
## 127.0.0.1 port (websocket transport); two client Sessions (alpha, beta) and later a
## late joiner (gamma) join over loopback, each in its own branch with its own
## SceneMultiplayer. Clients only read their own received snapshots. The server World is
## never touched after seeding; the on-disk save is read (file only) after shutdowns.
##
## SEEDED FIXTURE (disclosed): built offline in a World before the server starts and
## validated with SaveSchema. EARNED there through World.act: the canal repair (alpha),
## alpha's first 分水 memory, the plaque, and the whole 旱日分流 (alpha: revisit_gate
## a:3 / b:2, revisit_check ×3 on day 1). WRITTEN directly: repair materials, Lanyang
## standing spots used while earning, state.festival_story_open=true (the opening itself
## needs six projects + boat + lights; covered by the festival suites), the home standing
## spots of alpha (39.5,27.5) and beta (38.5,27.5) next to the exhibit stand (39,26),
## receipts cleared. No player has a memory_exhibit record. Beta never did her own 分水.
## Everything after the seed goes through client Sessions over the network; the late
## joiner gamma arrives at the spawn and walks (input_direction) to the stand.
## Replay: the raw request_action RPC re-sent with alpha's already-used view sequence;
## Session drops it.
## NOT covered: multiple processes, TLS, latency/loss, crash durability (normal shutdowns
## only), the stand fallback / pause (rule level, test_memory_exhibit.gd).
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Exhibit=preload("res://scripts/memory_exhibit.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Memory=preload("res://scripts/history_memory.gd")
const KEY:="memory-exhibit-session"
const ALPHA:="exhibit-session-alpha-token"
const BETA:="exhibit-session-beta-token"
const GAMMA:="exhibit-session-gamma-token"
const STAND:=Vector2i(39,26)
const A_SPOT:=Vector2(39.5,27.5)
const B_SPOT:=Vector2(38.5,27.5)

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
	func own()->Variant:
		return session.snapshot.get("own_memory_exhibit",null)
	func block()->Variant:
		return session.snapshot.get("memory_exhibit",null)

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
	print("MEMORY_EXHIBIT_SESSION watchdog fired before completion")
	print("MEMORY_EXHIBIT_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("MEMORY_EXHIBIT_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("MEMORY_EXHIBIT_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("MEMORY_EXHIBIT_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
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
	for cell:Vector2i in Memory.OBSERVATIONS:
		stand(w,ALPHA,cell)
		if not seed_act(w,ALPHA,"memory_observe",cell):return false
	stand(w,ALPHA,Memory.SERVICE)
	for pair in [[2,2],[1,3],[2,1]]:
		if not seed_act(w,ALPHA,"memory_gate",Memory.SERVICE,"a:%d"%pair[0]):return false
		if not seed_act(w,ALPHA,"memory_gate",Memory.SERVICE,"b:%d"%pair[1]):return false
		if not seed_act(w,ALPHA,"memory_flow",Memory.SERVICE):return false
	if not seed_act(w,ALPHA,"memory_plaque",Memory.SERVICE):return false
	w.state.history_memory.players[ALPHA].erase("completed_day")  # Legacy record for the day-one fixture.
	stand(w,ALPHA,Revisit.GATE_CELL)
	if not seed_act(w,ALPHA,Revisit.GATE_ACTION,Revisit.GATE_CELL,"a:3"):return false
	if not seed_act(w,ALPHA,Revisit.GATE_ACTION,Revisit.GATE_CELL,"b:2"):return false
	for field:String in Revisit.FIELDS:
		stand(w,ALPHA,Revisit.FIELD_CELLS[field])
		if not seed_act(w,ALPHA,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS[field]):return false
	if not Revisit.completed(w.state):return false
	w.state["festival_story_open"]=true
	var a:Dictionary=w.state.players[ALPHA]
	var b:Dictionary=w.state.players[BETA]
	for pair in [[a,A_SPOT],[b,B_SPOT]]:
		var p:Dictionary=pair[0]
		p["region"]="home"
		p["x"]=pair[1].x
		p["y"]=pair[1].y
		p["receipts"]={}
	w.active_tokens.clear()
	w.save_path=path
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.players[ALPHA].has(Exhibit.RECORD_KEY) or parsed.players[BETA].has(Exhibit.RECORD_KEY):return false
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
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty() and c.own() is Dictionary

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

## Walk with real input along a cardinal direction until crossing a coordinate.
func walk_to_line(c:Client,direction:Vector2,target:float)->bool:
	var axis:="x" if direction.x!=0.0 else "y"
	var arrived:=await wait_until(func():
		c.session.input_direction(direction)
		return float(c.me().get(axis,99.0))<=target,8.0)
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
	return clients.map(func(x):return [text(canon(x.bag())),text(x.own()),text(x.block())])

func refuse(c:Client,action:String,p:Vector2i,extra:String,message:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var marks:=marks_of(everyone)
	var r:=await act(c,action,p,extra)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	expect(marks_of(everyone)==marks,"%s: bags, own and public exhibit blocks unchanged in every watching snapshot"%label)

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
	var people=c.session.snapshot.get("players",{})
	var records:=false
	if people is Dictionary:
		for id in people:
			if people[id] is Dictionary and (people[id] as Dictionary).has(Exhibit.RECORD_KEY):records=true
	expect(not records,"%s: %s's snapshot carries no player's memory_exhibit record"%[label,c.label])
	expect(dump.count("\"own_memory_exhibit\"")==1,"%s: %s's snapshot has exactly one own block"%[label,c.label])

func public_ok(c:Client)->bool:
	return text(c.block())==text({"cell":STAND,"paused":false,"on_display":["lanyang"],"blocked_cells":[]})

func own_is(c:Client,seen:Array,ready:bool,claimed:bool)->bool:
	# The own block also carries the 礦燈 keys (金瓜石回訪); nobody in this fixture has them.
	return text(c.own())==text({"seen":seen,"first_share_done":ready,"plaque_claimed":claimed,"sorting_done":false,"lantern_claimed":false,"comparison_done":false,"teaware_claimed":false,"raking_done":false,"basket_claimed":false})

func read_disk()->Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(save_path))

func disk_valid(disk:Variant)->bool:
	return disk is Dictionary and Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("memory-exhibit-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"SEEDED FIXTURE (repair, alpha memory, plaque, revisit earned offline; festival flag and spots written; no exhibit records) accepted by SaveSchema"):return false
	var probe:=World.new()
	if not expect(probe.load_world(save_path),"probe: seeded save loads"):return false
	expect(probe.can_stand(A_SPOT) and probe.can_stand(B_SPOT) and probe.can_stand(Vector2(World.SPAWN)) and probe.blocked(STAND),"probe: both spots and the spawn standable, stand blocking")
	probe=null
	var port:=start_server()
	if not expect(port>0,"server Session hosts on 127.0.0.1 (websocket)"):return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	if not expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback"):return false
	expect(server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer,"server and clients use WebSocketMultiplayerPeer")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World")
	await settle([alpha,beta])
	print("MEMORY_EXHIBIT_SESSION_LABEL machine=single process=single transport=websocket loopback=127.0.0.1:%d clients=2(+late joiner) fixture=SEEDED(repair,memory,plaque,revisit earned offline; festival flag, spots written) shutdown=normal-only"%port)

	# 1. Both see the stand and the plaque on display, unread; personal state differs.
	for c:Client in [alpha,beta]:
		var snap:Dictionary=c.session.snapshot
		expect(public_ok(c),"case 1 %s: public block (%s)"%[c.label,text(c.block())])
		expect(Exhibit.unlocked(snap) and Exhibit.stand_cell(snap)==STAND and Exhibit.on_display_ids(snap)==["lanyang"] and Exhibit.unread_count(snap)==1,"case 1 %s: client helpers see lanyang on display and unread"%c.label)
		expect(Exhibit.recap_pages("lanyang",snap).size()==4 and Exhibit.recap(snap).get("demand")==[6,4,2],"case 1 %s: recap available on the client"%c.label)
		private_check(c,[beta if c==alpha else alpha],"case 1")
	expect(own_is(alpha,[],true,false) and Exhibit.personal_hint(alpha.session.snapshot)==Exhibit.HINT_UNCLAIMED,"case 1 alpha: own block, plaque waiting")
	expect(own_is(beta,[],false,false) and Exhibit.personal_hint(beta.session.snapshot)==Exhibit.HINT_NOT_READY,"case 1 beta: own block, catch-up hint")

	# 2. Refusals leave both ends unchanged.
	await refuse(alpha,Exhibit.VIEW_ACTION,STAND,"jinguashi",Exhibit.NOT_ON_DISPLAY,"case 2 empty pedestal",[beta])
	await refuse(alpha,Exhibit.VIEW_ACTION,STAND,"bogus",Exhibit.UNKNOWN_EXHIBIT,"case 2 unknown exhibit",[beta])
	await refuse(beta,Exhibit.VIEW_ACTION,Exhibit.CANDIDATES[1],"lanyang",Exhibit.WRONG_POINT,"case 2 wrong stand cell",[alpha])

	# 3. Alpha views; only alpha's own block changes.
	var first:=await succeed(alpha,Exhibit.VIEW_ACTION,STAND,"lanyang","case 3 alpha views the plaque",[beta])
	expect(str(first.message)==Exhibit.VIEW_OK%"分水木牌","case 3 view message")
	await wait_until(func():return own_is(alpha,["lanyang"],true,false),3.0)
	expect(own_is(alpha,["lanyang"],true,false) and Exhibit.unread_count(alpha.session.snapshot)==0,"case 3 alpha's own block shows seen, unread 0")
	expect(own_is(beta,[],false,false) and Exhibit.unread_count(beta.session.snapshot)==1,"case 3 beta's own block unchanged (A's seen invisible to B)")
	expect(public_ok(alpha) and public_ok(beta),"case 3 public block unchanged for both")
	for c:Client in [alpha,beta]:private_check(c,[beta if c==alpha else alpha],"case 3")

	# 4. Replay of a used sequence is dropped; a new request is ALREADY_SEEN.
	await settle([alpha,beta])
	var counts:=[alpha.notices.size(),beta.notices.size()]
	var before4:=marks_of([alpha,beta])
	alpha.session.request_action.rpc_id(1,int(first.sequence),Exhibit.VIEW_ACTION,STAND,"lanyang",str(alpha.session.snapshot.get("region_id","")),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==counts[0] and beta.notices.size()==counts[1],"case 4 re-sent sequence %d gets no notice"%int(first.sequence))
	expect(marks_of([alpha,beta])==before4,"case 4 re-sent sequence changes nothing on either end")
	await refuse(alpha,Exhibit.VIEW_ACTION,STAND,"lanyang",Exhibit.ALREADY_SEEN,"case 4 alpha views again",[beta])

	# 5. Beta (no own 分水) views independently.
	await succeed(beta,Exhibit.VIEW_ACTION,STAND,"lanyang","case 5 beta views the plaque",[alpha])
	await wait_until(func():return own_is(beta,["lanyang"],false,false),3.0)
	expect(own_is(beta,["lanyang"],false,false) and own_is(alpha,["lanyang"],true,false),"case 5 both own blocks seen, flags unchanged")
	expect(Exhibit.personal_hint(beta.session.snapshot)==Exhibit.HINT_NOT_READY,"case 5 beta still gets the catch-up hint")

	# 6. Reconnect keeps seen.
	await leave(alpha)
	alpha=null
	await pause(0.3)
	alpha=await join("alpha",ALPHA,port)
	if not expect(joined(alpha),"case 6 alpha reconnects"):return false
	await settle([alpha,beta])
	expect(own_is(alpha,["lanyang"],true,false) and Exhibit.unread_count(alpha.session.snapshot)==0,"case 6 reconnected alpha still has seen it")
	await refuse(alpha,Exhibit.VIEW_ACTION,STAND,"lanyang",Exhibit.ALREADY_SEEN,"case 6 reconnected alpha views again",[beta])

	# 7. Normal shutdown -> exact save, field by field.
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 7 server shuts down with a final save")
	var disk=read_disk()
	if not expect(disk is Dictionary,"case 7 save parses"):return false
	expect(disk_valid(disk),"case 7 saved world passes SaveSchema")
	expect(not disk.has(Exhibit.STATE_KEY) and disk.get("festival_story_open")==true,"case 7 save: no top-level exhibit block, festival flag kept")
	for token in [ALPHA,BETA]:
		var rec=disk.players[token].get(Exhibit.RECORD_KEY)
		expect(rec is Dictionary and rec.size()==1 and text(rec.get("seen"))==text(["lanyang"]),"case 7 save: %s record exactly {seen:[lanyang]} (%s)"%[token.left(20),text(rec)])
	var rev=disk.get(Revisit.STATE_KEY,{})
	expect(rev is Dictionary and rev.get("completed")==true and text(rev.get("claimed",{}))==text({}),"case 7 save: revisit record untouched (completed, nobody claimed)")

	# 8. Restart; late joiner.
	var port2:=start_server()
	if not expect(port2>0,"case 8 restarted server hosts the same save"):return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	if not expect(joined(alpha) and joined(beta),"case 8 both rejoin"):return false
	await settle([alpha,beta])
	expect(own_is(alpha,["lanyang"],true,false) and own_is(beta,["lanyang"],false,false) and public_ok(alpha) and public_ok(beta),"case 8 restart consistent")
	gamma=await join("gamma",GAMMA,port2)
	if not expect(joined(gamma),"case 8 late joiner gamma joins"):return false
	await settle([alpha,beta,gamma])
	var g:Dictionary=gamma.session.snapshot
	expect(public_ok(gamma) and own_is(gamma,[],false,false),"case 8 gamma sees the stand; own block empty")
	expect(Exhibit.unread_count(g)==1 and Exhibit.exhibits(g)[0].unread==true and Exhibit.personal_hint(g)==Exhibit.HINT_NOT_READY,"case 8 gamma: lanyang on display and unread, catch-up hint")
	private_check(gamma,[alpha,beta],"case 8")
	await refuse(gamma,Exhibit.VIEW_ACTION,STAND,"lanyang",Exhibit.TOO_FAR,"case 8 gamma at the spawn is too far",[alpha,beta])
	expect(await walk_to_line(gamma,Vector2.LEFT,float(STAND.x)+0.7),"case 8 gamma walks west from the ferry")
	expect(await walk_to_line(gamma,Vector2.UP,float(STAND.y)+3.4),"case 8 gamma walks north to the stand")
	await succeed(gamma,Exhibit.VIEW_ACTION,STAND,"lanyang","case 8 gamma views the plaque",[alpha,beta])
	await wait_until(func():return own_is(gamma,["lanyang"],false,false),3.0)
	expect(own_is(gamma,["lanyang"],false,false) and Exhibit.unread_count(gamma.session.snapshot)==0,"case 8 gamma marked seen")
	expect(own_is(alpha,["lanyang"],true,false) and own_is(beta,["lanyang"],false,false),"case 8 gamma's view does not touch alpha/beta")
	await leave(gamma)
	gamma=null
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 8 restarted server shuts down cleanly")
	var after=read_disk()
	expect(disk_valid(after),"case 8 final save valid")
	if after is Dictionary:
		expect(after.players.has(GAMMA) and text(after.players[GAMMA].get(Exhibit.RECORD_KEY))==text({"seen":["lanyang"]}),"case 8 final save: gamma seen")
		for token in [ALPHA,BETA]:
			expect(text(after.players[token].get(Exhibit.RECORD_KEY))==text(disk.players[token].get(Exhibit.RECORD_KEY)),"case 8 final save: %s record unchanged"%token.left(20))
		expect(text(after.get(Revisit.STATE_KEY))==text(disk.get(Revisit.STATE_KEY)),"case 8 final save: revisit record unchanged")
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
