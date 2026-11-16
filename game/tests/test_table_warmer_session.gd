extends SceneTree
## T067 共餐桌保溫底座 two-client Session acceptance over a real dedicated server and
## real WebSocket clients (modelled on test_souvenir_exchange_session.gd).
##
## LEVEL: one machine, ONE Godot process. A dedicated server Session listens on a free
## 127.0.0.1 port (websocket transport); two client Sessions (alpha, beta) and later a
## late joiner (gamma) join over loopback, each in its own branch with its own
## SceneMultiplayer. Clients only read their own received snapshots. The server World is
## never touched after seeding; the on-disk save is read (file only) after shutdowns.
##
## SEEDED FIXTURE (disclosed): built offline in a World before the server starts and
## validated with SaveSchema. The picnic is EARNED there through World.act "picnic"
## (board=true and soup 2 / bread 1 written first), so the shared table sits at 39,30.
## Written directly after that: positions (alpha 40.5,30.5; beta 38.5,30.5) and exact
## bags — alpha {warm_stone 6, copper_joint 2, stone 4, trout_hotpot 7}, beta
## {warm_stone 5, copper_joint 2, stone 4, trout_hotpot 1}. Mining warm_stone is covered
## at rule level (test_table_warmer.gd). No table_warmer key is ever preset.
## Everything after the seed goes through client Sessions over the network.
## Replay: the raw request_action RPC re-sent with alpha's already-used install sequence
## number but the serve_hotpot_warm action; Session drops it.
## NOT covered: multiple processes, TLS, latency/loss, crash durability (normal shutdowns
## only), wrong-region / too-far refusals (rule level).
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Warmer=preload("res://scripts/table_warmer.gd")
const Community=preload("res://scripts/community.gd")
const KEY:="table-warmer-session"
const ALPHA:="warmer-session-alpha-token"
const BETA:="warmer-session-beta-token"
const GAMMA:="warmer-session-gamma-token"
const TABLE:=Vector2i(39,30)
const BOARD:=Vector2i(40,29)
const A_SPOT:=Vector2(40.5,30.5)
const B_SPOT:=Vector2(38.5,30.5)
const ALPHA_BAG:={"warm_stone":6,"copper_joint":2,"stone":4,"trout_hotpot":7}
const BETA_BAG:={"warm_stone":5,"copper_joint":2,"stone":4,"trout_hotpot":1}

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
	func warmer()->Variant:
		return session.snapshot.get("table_warmer",null)
	func hotpot()->Dictionary:
		var c=session.snapshot.get("community",{})
		var h=c.get("hotpot",{}) if c is Dictionary else {}
		return h if h is Dictionary else {}

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
	create_timer(100.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("TABLE_WARMER_SESSION watchdog fired before completion")
	print("TABLE_WARMER_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("TABLE_WARMER_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("TABLE_WARMER_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("TABLE_WARMER_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

func seed_world(path:String)->bool:
	var w:=World.new()
	w.add_player(ALPHA,"alpha")
	w.add_player(BETA,"beta")
	w.state["board"]=true
	var a:Dictionary=w.state.players[ALPHA]
	a["x"]=A_SPOT.x
	a["y"]=A_SPOT.y
	a.inventory["soup"]=2
	a.inventory["bread"]=1
	var b:Dictionary=w.state.players[BETA]
	b["x"]=B_SPOT.x
	b["y"]=B_SPOT.y
	if not w.act(ALPHA,"seed-picnic","picnic",BOARD).ok:return false
	if Community.table_cell(w.state)!=TABLE:return false
	a["inventory"]=ALPHA_BAG.duplicate()
	b["inventory"]=BETA_BAG.duplicate()
	for p:Dictionary in [a,b]:p["receipts"]={}
	w.active_tokens.clear()
	w.save_path=path
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.has("table_warmer"):return false
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
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty() and c.session.snapshot.get("community") is Dictionary

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

# ---------------------------------------------------------------- helpers --

static func canon(d:Variant)->Dictionary:
	var out:={}
	if not d is Dictionary:return {"<invalid>":-1}
	for item in d:
		if int(d[item])!=0:out[str(item)]=int(d[item])
	return out

static func text(d:Variant)->String:
	return JSON.stringify(d,"",true)

## Public view of the hotpot round (portions/total/claimed_own), stringified.
static func meal_row(h:Dictionary)->String:
	if h.is_empty():return "{}"
	return text({"portions":int(h.get("portions",-1)),"total":int(h.get("total",-1)),"claimed_own":h.get("claimed_own"),"has_claimed_map":h.has("claimed")})

func marks_of(clients:Array)->Array:
	return clients.map(func(x):return [text(canon(x.bag())),text(x.warmer()),meal_row(x.hotpot())])

func refuse(c:Client,action:String,p:Vector2i,extra:String,message:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var marks:=marks_of(everyone)
	var r:=await act(c,action,p,extra)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	expect(marks_of(everyone)==marks,"%s: bags, table_warmer and hotpot unchanged in every watching snapshot"%label)

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
	expect(not c.hotpot().has("claimed"),"%s: %s's snapshot carries no hotpot claim map"%[label,c.label])

func read_disk()->Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(save_path))

func disk_valid(disk:Variant)->bool:
	return disk is Dictionary and Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("table-warmer-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"SEEDED FIXTURE (picnic earned offline, positions and bags written, no table_warmer) accepted by SaveSchema"):return false
	var probe:=World.new()
	if not expect(probe.load_world(save_path),"probe: seeded save loads"):return false
	for spot:Vector2 in [A_SPOT,B_SPOT]:expect(probe.can_stand(spot) and spot.distance_to(Vector2(TABLE)+Vector2(0.5,0.5))<=Warmer.REACH,"probe: %s standable and within reach of the table"%str(spot))
	probe=null
	var port:=start_server()
	if not expect(port>0,"server Session hosts on 127.0.0.1 (websocket)"):return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	if not expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback"):return false
	var ws:bool=server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer
	expect(ws,"server and clients use WebSocketMultiplayerPeer")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World")
	await settle([alpha,beta])
	print("TABLE_WARMER_SESSION_LABEL machine=single process=single transport=websocket loopback=127.0.0.1:%d clients=2(+late joiner) fixture=SEEDED(picnic earned offline,positions,bags) shutdown=normal-only"%port)

	# 1. Fresh: no base anywhere.
	for c:Client in [alpha,beta]:
		expect(c.warmer()==null and not Warmer.installed(c.session.snapshot),"case 1 %s: no table_warmer in the snapshot"%c.label)
		expect(Community.table_cell(c.session.snapshot)==TABLE,"case 1 %s: table cell 39,30 computable from the snapshot"%c.label)
		private_check(c,[beta if c==alpha else alpha],"case 1")
	expect(canon(alpha.bag())==canon(ALPHA_BAG) and canon(beta.bag())==canon(BETA_BAG),"case 1 preset bags arrive unchanged")
	expect(Warmer.can_install(alpha.session.snapshot,alpha.bag()) and Warmer.install_block(beta.session.snapshot,beta.bag())==Warmer.SHORT%"暖岩片 1","case 1 client-side helpers: alpha can install, beta is one warm stone short")

	# 2. Refusals: both ends unchanged.
	await refuse(alpha,Warmer.SERVE_ACTION,TABLE,"",Warmer.NOT_INSTALLED,"case 2 warm serve before the base",[beta])
	await refuse(alpha,Warmer.INSTALL_ACTION,Vector2i(40,31),"",Warmer.WRONG_CELL,"case 2 install at the wrong cell",[beta])
	await refuse(alpha,Warmer.INSTALL_ACTION,TABLE,"now",Warmer.BAD_EXTRA,"case 2 install with an extra",[beta])
	await refuse(beta,Warmer.INSTALL_ACTION,TABLE,"",Warmer.SHORT%"暖岩片 1","case 2 beta one warm stone short",[alpha])

	# 3. Alpha installs; both see it.
	var installed:=await succeed(alpha,Warmer.INSTALL_ACTION,TABLE,"","case 3 alpha installs the base",[beta])
	expect(str(installed.message)==Warmer.INSTALLED_OK,"case 3 install message")
	await wait_until(func():return Warmer.installed(alpha.session.snapshot) and Warmer.installed(beta.session.snapshot),3.0)
	for c:Client in [alpha,beta]:
		expect(text(c.warmer())==text({"installed":true}),"case 3 %s sees table_warmer {installed:true}"%c.label)
	expect(canon(alpha.bag())==canon({"trout_hotpot":7}),"case 3 alpha paid exactly warm_stone 6, copper_joint 2, stone 4 (bag %s)"%text(canon(alpha.bag())))
	expect(canon(beta.bag())==canon(BETA_BAG),"case 3 beta's bag unchanged")

	# 4. Replay of the used sequence (with another action) is dropped.
	await settle([alpha,beta])
	var counts:=[alpha.notices.size(),beta.notices.size()]
	var before4:=marks_of([alpha,beta])
	alpha.session.request_action.rpc_id(1,int(installed.sequence),Warmer.SERVE_ACTION,TABLE,"",str(alpha.session.snapshot.get("region_id","")),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==counts[0] and beta.notices.size()==counts[1],"case 4 re-sent sequence %d gets no notice"%int(installed.sequence))
	expect(marks_of([alpha,beta])==before4 and alpha.hotpot().is_empty(),"case 4 re-sent sequence changes nothing on either end (no hotpot served)")
	await refuse(beta,Warmer.INSTALL_ACTION,TABLE,"",Warmer.ALREADY,"case 4 a second base is refused",[alpha])

	# 5. Warm serve + claims by both.
	await succeed(alpha,Warmer.SERVE_ACTION,TABLE,"","case 5 alpha serves six warm portions",[beta])
	await wait_until(func():return int(beta.hotpot().get("portions",0))==6,3.0)
	for c:Client in [alpha,beta]:
		expect(int(c.hotpot().get("portions",-1))==6 and int(c.hotpot().get("total",-1))==6 and c.hotpot().get("claimed_own")==false,"case 5 %s sees 6/6 portions, not yet claimed"%c.label)
	expect(canon(alpha.bag())==canon({"trout_hotpot":1}),"case 5 alpha's six hotpots left the bag")
	await refuse(alpha,Warmer.SERVE_ACTION,TABLE,"",Warmer.STILL_SERVING,"case 5 warm serve while portions remain",[beta])
	await succeed(alpha,"claim_hotpot",TABLE,"","case 5 alpha claims one",[beta])
	await succeed(beta,"claim_hotpot",TABLE,"","case 5 beta claims one",[alpha])
	await wait_until(func():return int(alpha.hotpot().get("portions",0))==4 and int(beta.hotpot().get("portions",0))==4,3.0)
	for c:Client in [alpha,beta]:
		expect(int(c.hotpot().get("portions",-1))==4 and int(c.hotpot().get("total",-1))==6 and c.hotpot().get("claimed_own")==true,"case 5 %s sees 4/6 left and its own claim"%c.label)
		private_check(c,[beta if c==alpha else alpha],"case 5")
	expect(canon(alpha.bag())==canon({"trout_hotpot":2}) and canon(beta.bag())==canon({"warm_stone":5,"copper_joint":2,"stone":4,"trout_hotpot":2}),"case 5 each claimer gained exactly one hotpot")
	await refuse(beta,"claim_hotpot",TABLE,"","你已領過這一輪，剩下的留給其他島民。","case 5 beta re-claims",[alpha])

	# 6. Disconnect / reconnect cannot re-claim.
	await leave(beta)
	beta=null
	await pause(0.3)
	beta=await join("beta",BETA,port)
	if not expect(joined(beta),"case 6 beta reconnects"):return false
	await settle([alpha,beta])
	expect(Warmer.installed(beta.session.snapshot) and beta.hotpot().get("claimed_own")==true and int(beta.hotpot().get("portions",-1))==4,"case 6 reconnected beta sees the base, 4 portions and its own claim")
	await refuse(beta,"claim_hotpot",TABLE,"","你已領過這一輪，剩下的留給其他島民。","case 6 reconnected beta cannot re-claim",[alpha])

	# 7. Normal shutdown → exact save.
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 7 server shuts down with a final save")
	var disk=read_disk()
	if not expect(disk is Dictionary,"case 7 save parses"):return false
	expect(disk_valid(disk),"case 7 saved world passes SaveSchema")
	expect(text(disk.get("table_warmer"))==text({"installed":true}),"case 7 save: table_warmer {installed:true}")
	var hot=disk.community.get("hotpot",{})
	expect(int(hot.get("portions",-1))==4 and int(hot.get("total",-1))==6 and hot.size()==3,"case 7 save: hotpot 4 left of 6 (%s)"%text(hot))
	var claimers:Array=hot.get("claimed",{}).keys()
	claimers.sort()
	var want:=[ALPHA,BETA]
	want.sort()
	expect(claimers==want,"case 7 save: exactly alpha and beta claimed")
	expect(canon(disk.players[ALPHA].inventory)==canon({"trout_hotpot":2}) and canon(disk.players[BETA].inventory)==canon({"warm_stone":5,"copper_joint":2,"stone":4,"trout_hotpot":2}),"case 7 save: both exact bags")
	expect(str(disk.community.table)=="39,30","case 7 save: the table did not move")

	# 8. Restart; late joiner sees the base and can claim once.
	var port2:=start_server()
	if not expect(port2>0,"case 8 restarted server hosts the same save"):return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	if not expect(joined(alpha) and joined(beta),"case 8 both rejoin"):return false
	await settle([alpha,beta])
	for c:Client in [alpha,beta]:
		expect(Warmer.installed(c.session.snapshot) and int(c.hotpot().get("portions",-1))==4 and int(c.hotpot().get("total",-1))==6 and c.hotpot().get("claimed_own")==true,"case 8 %s: restart consistent (base, 4/6, own claim)"%c.label)
	gamma=await join("gamma",GAMMA,port2)
	if not expect(joined(gamma),"case 8 late joiner gamma joins"):return false
	await settle([alpha,beta,gamma])
	expect(text(gamma.warmer())==text({"installed":true}) and gamma.hotpot().get("claimed_own")==false and int(gamma.hotpot().get("portions",-1))==4,"case 8 gamma sees the base and an unclaimed 4/6 round")
	private_check(gamma,[alpha,beta],"case 8")
	await refuse(gamma,Warmer.INSTALL_ACTION,TABLE,"",Warmer.ALREADY,"case 8 gamma cannot install again",[alpha,beta])
	await leave(gamma)
	gamma=null
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 8 restarted server shuts down cleanly")
	var after=read_disk()
	expect(disk_valid(after) and text(after.get("table_warmer"))==text({"installed":true}) and int(after.community.hotpot.portions)==4 and after.players.has(GAMMA),"case 8 final save valid, base kept, round unchanged, gamma recorded")
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
