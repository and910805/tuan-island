extends SceneTree
## 第 40 章家園「水塔」water_tower two-client Session acceptance over a real dedicated server
## and real WebSocket clients (modelled on test_lanyang_revisit_session.gd).
##
## LEVEL: one machine, ONE Godot process. A dedicated server Session listens on a free
## 127.0.0.1 port (websocket transport); two client Sessions (alpha = owner, beta =
## visitor) and later a late joiner (gamma) join over loopback, each in its own branch
## with its own SceneMultiplayer. Clients only read their own received snapshots. The
## server World is never touched after seeding; the on-disk save is read (file only)
## after shutdowns.
##
## SEEDED FIXTURE (disclosed): built offline in a World before the server starts and
## validated with SaveSchema. EARNED there through World.act: the canal repair (alpha:
## lanyang_clear ×3, lanyang_donate), alpha's first 分水 memory (memory_observe ×3,
## memory_gate/memory_flow ×3), the plaque, and the Lanyang revisit itself (alpha:
## revisit_gate a:3 / b:2, revisit_check upstream / middle / tail on day 1 spring ->
## completed, which unlocks the tower recipe), and alpha's workbench at (50,22).
## WRITTEN DIRECTLY: repair materials, wood/stone for the bench, then alpha's bag set to
## exactly plank 6 / copper_joint 2 / stone 6 / tank_kit 1, every standing spot (Lanyang
## spots for the seed actions; home spots next to the bench/tank/tower cells for alpha
## and beta, region "home"), receipts cleared. NOTHING of the tower is pre-placed: the
## tower kit is crafted, the tank and the tower are built, the tank is refilled and the
## tower toggled by alpha's client over the network. World time starts at 0 and only
## advances by the server's real-time ticks (one network round per 8 s of real time).
## Duplicate / replay: raw request_action RPCs (a) the same fresh sequence sent twice
## back-to-back (alpha's client counter advanced by the test so its next perform() does
## not reuse it) and (b) an already-used sequence re-sent later.
## NOT covered: multiple processes, TLS, latency/loss, crash durability (normal shutdowns
## only), sprinkler feeding / gate zones (rule test + journey).
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Memory=preload("res://scripts/history_memory.gd")
const Industry=preload("res://scripts/industry.gd")
const KEY:="water-tower-session"
const ALPHA:="tower-session-alpha-token"
const BETA:="tower-session-beta-token"
const GAMMA:="tower-session-gamma-token"
const BENCH:=Vector2i(50,22)
const TANK:=Vector2i(49,22)
const TOWER:=Vector2i(48,22)
const TOWER_KEY:="48,22"
const GATE:=Vector2i(47,22)
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
	func tower()->Dictionary:
		var objs=session.snapshot.get("objects",{})
		if not objs is Dictionary:return {}
		var o=objs.get(TOWER_KEY,{})
		return o if o is Dictionary else {}

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
var home_spots:={}
var levels:=[]

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)
	return ok

func _initialize()->void:
	create_timer(105.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("WATER_TOWER_SESSION watchdog fired before completion")
	print("WATER_TOWER_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("WATER_TOWER_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("WATER_TOWER_SESSION tower levels seen %s"%str(levels))
	print("WATER_TOWER_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("WATER_TOWER_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

func seed_act(w:World,token:String,action:String,p:Vector2i,extra:String="")->bool:
	serial+=1
	var r:=w.act(token,"seed-%d"%serial,action,p,extra)
	if not r.ok:print("WATER_TOWER_SESSION seed action %s %s %s refused: %s"%[action,str(p),extra,str(r.message)])
	return bool(r.ok)

func stand(w:World,token:String,cell:Vector2i)->void:
	var p:Dictionary=w.state.players[token]
	p["region"]="lanyang"
	p["x"]=cell.x-0.5
	p["y"]=cell.y+0.5

func place(w:World,token:String,region:String,spot:Vector2)->void:
	var p:Dictionary=w.state.players[token]
	p["region"]=region
	p["x"]=spot.x
	p["y"]=spot.y

## Standable home tiles within 3.0 of every target cell centre (bench/tank/tower cells excluded).
func home_spot(w:World,targets:Array,taken:Array)->Vector2:
	for y in range(20,32):
		for x in range(42,56):
			var tile:=Vector2i(x,y)
			if tile in [BENCH,TANK,TOWER,GATE] or tile in taken:continue
			var at:=Vector2(x+0.5,y+0.5)
			if not w.can_stand(at):continue
			var ok:=true
			for t:Vector2i in targets:
				if at.distance_to(Vector2(t)+Vector2(0.5,0.5))>3.0:ok=false
			if ok:return at
	return Vector2(-1,-1)

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
	# The revisit (day 1, spring, demand 6/4/2 -> gates a:3 b:2).
	place(w,ALPHA,"lanyang",A_SPOT)
	if not seed_act(w,ALPHA,Revisit.GATE_ACTION,Revisit.GATE_CELL,"a:3"):return false
	if not seed_act(w,ALPHA,Revisit.GATE_ACTION,Revisit.GATE_CELL,"b:2"):return false
	if not seed_act(w,ALPHA,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS.upstream):return false
	place(w,ALPHA,"lanyang",B_SPOT)
	if not seed_act(w,ALPHA,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS.middle):return false
	if not seed_act(w,ALPHA,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS.tail):return false
	if not Revisit.completed(w.state) or not Revisit.tech_unlocked(w.state):return false
	# Home: alpha's bench, then the exact tower-kit materials and one tank kit.
	var a_spot:=home_spot(w,[BENCH,TANK,TOWER],[])
	if a_spot.x<0:return false
	place(w,ALPHA,"home",a_spot)
	var inv:Dictionary=w.state.players[ALPHA].inventory
	inv["wood"]=20
	inv["stone"]=5
	if not seed_act(w,ALPHA,"build",BENCH,"bench"):return false
	for item in inv.keys():inv[item]=0
	inv["plank"]=6
	inv["copper_joint"]=2
	inv["stone"]=6
	inv["tank_kit"]=1
	inv["diversion_gate_kit"]=1
	a_spot=home_spot(w,[BENCH,TANK,TOWER,GATE],[])
	var b_spot:=home_spot(w,[TOWER,GATE],[Vector2i(floori(a_spot.x),floori(a_spot.y))])
	if a_spot.x<0 or b_spot.x<0:return false
	place(w,ALPHA,"home",a_spot)
	place(w,BETA,"home",b_spot)
	home_spots={"alpha":a_spot,"beta":b_spot}
	for t in [ALPHA,BETA]:w.state.players[t]["receipts"]={}
	w.active_tokens.clear()
	w.save_path=path
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or float(parsed.time)!=0.0 or JSON.stringify(parsed.objects).contains("water_tower"):return false
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
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty() and c.session.snapshot.get("objects") is Dictionary

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

## Public tower row as a client sees it (owner is the public id, never the token).
static func row_of(o:Dictionary)->String:
	if o.is_empty():return "none"
	return text({"type":o.get("type"),"owner":o.get("owner"),"items":o.get("items"),"water":int(o.get("water",-1)),"enabled":o.get("enabled")})

static func want_row(water:int,enabled:bool)->String:
	return text({"type":"water_tower","owner":ALPHA.sha256_text().left(16),"items":{},"water":water,"enabled":enabled})

func marks_of(clients:Array)->Array:
	return clients.map(func(x):return [text(canon(x.bag())),row_of(x.tower())])

func refuse(c:Client,action:String,p:Vector2i,extra:String,message:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var marks:=marks_of(everyone)
	var r:=await act(c,action,p,extra)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	expect(marks_of(everyone)==marks,"%s: bags and the tower unchanged in every watching snapshot"%label)

func succeed(c:Client,action:String,p:Vector2i,extra:String,label:String,watchers:Array)->Dictionary:
	var r:=await act(c,action,p,extra)
	expect(r.replied and r.ok,"%s: ok (got ok=%s '%s')"%[label,str(r.ok),str(r.message)])
	await settle([c]+watchers)
	return r

func all_see(clients:Array,want:String,seconds:float)->bool:
	return await wait_until(func():
		for c:Client in clients:
			if row_of(c.tower())!=want:return false
		return true,seconds)

func private_check(c:Client,others:Array,label:String)->void:
	var dump:=JSON.stringify(c.session.snapshot)
	var leaked:=false
	for o:Client in others+[c]:
		if dump.contains(o.token):leaked=true
	expect(not leaked,"%s: %s's snapshot contains no raw token"%[label,c.label])

func read_disk()->Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(save_path))

func disk_valid(disk:Variant)->bool:
	return disk is Dictionary and Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

## Field-by-field check of the saved tower object.
func disk_tower_ok(disk:Variant,water:int,enabled:bool,label:String)->void:
	var o=disk.get("objects",{}).get(TOWER_KEY,null) if disk is Dictionary else null
	if not expect(o is Dictionary,"%s: saved tower object present"%label):return
	var keys:Array=o.keys()
	keys.sort()
	expect(keys==["enabled","items","owner","type","water"],"%s: saved tower has exactly enabled/items/owner/type/water (%s)"%[label,str(keys)])
	expect(str(o.get("type"))=="water_tower","%s: type water_tower"%label)
	expect(str(o.get("owner"))==ALPHA,"%s: owner alpha (raw token on disk)"%label)
	expect(o.get("items") is Dictionary and (o.get("items") as Dictionary).is_empty(),"%s: items {}"%label)
	expect((o.get("water") is float or o.get("water") is int) and int(o.get("water"))==water and float(o.get("water"))==float(water),"%s: water %d (got %s)"%[label,water,str(o.get("water"))])
	expect(o.get("enabled") is bool and o.get("enabled")==enabled,"%s: enabled %s (got %s)"%[label,str(enabled),str(o.get("enabled"))])

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("water-tower-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"SEEDED FIXTURE (repair, memory, plaque, revisit and bench earned offline; materials, tank kit and spots written; no tower) accepted by SaveSchema"):return false
	print("WATER_TOWER_SESSION seed spots %s"%str(home_spots))
	var port:=start_server()
	if not expect(port>0,"server Session hosts on 127.0.0.1 (websocket)"):return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	if not expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback"):return false
	expect(server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer,"server and clients use WebSocketMultiplayerPeer")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World")
	await settle([alpha,beta])
	print("WATER_TOWER_SESSION_LABEL machine=single process=single transport=websocket loopback=127.0.0.1:%d clients=2(+late joiner) fixture=SEEDED(revisit+bench earned offline; materials, tank kit, spots written; no tower) shutdown=normal-only"%port)
	for c:Client in [alpha,beta]:
		expect(Revisit.tech_unlocked(c.session.snapshot) and c.tower().is_empty(),"case 1 %s: revisit completed (tower tech unlocked), no tower yet"%c.label)
		private_check(c,[beta if c==alpha else alpha],"case 1")

	# 2. Alpha crafts the kit, builds a tank and the tower; both see it.
	var bag0:=canon(alpha.bag())
	var craft:=await succeed(alpha,"craft",BENCH,Industry.TOWER_KIT,"case 2 alpha crafts the tower kit at the bench",[beta])
	expect(str(craft.message)=="製作完成：水塔","case 2 craft message")
	var want_bag:=bag0.duplicate()
	for item in ["plank","copper_joint","stone"]:want_bag.erase(item)
	want_bag[Industry.TOWER_KIT]=1
	await wait_until(func():return canon(alpha.bag())==want_bag,3.0)
	expect(canon(alpha.bag())==want_bag,"case 2 alpha's bag: exactly plank -6 / copper_joint -2 / stone -6 / kit +1 (%s)"%text(canon(alpha.bag())))
	await refuse(beta,"build",TOWER,Industry.TOWER_KIND,"材料不足，需要水塔 1","case 2 beta without a kit cannot build a tower",[alpha])
	await succeed(alpha,"build",TANK,"water_tank","case 2 alpha builds the tank",[beta])
	await succeed(alpha,"build",TOWER,Industry.TOWER_KIND,"case 2 alpha builds the tower",[beta])
	expect(await all_see([alpha,beta],want_row(0,true),3.0),"case 2 both see the tower: water 0, 出水, owner alpha's public id (alpha %s, beta %s)"%[row_of(alpha.tower()),row_of(beta.tower())])
	for c:Client in [alpha,beta]:
		var rep:=Industry.tower_report(c.session.snapshot,TOWER_KEY)
		expect(rep.ok and int(rep.water)==0 and rep.enabled==true and rep.refill_zone=="full" and int(rep.tanks)==1 and rep.consumers==[],"case 2 %s tower_report on the client snapshot (%s)"%[c.label,str(rep)])
		private_check(c,[beta if c==alpha else alpha],"case 2")

	# 3. Real server rounds refill the tower from the tank; both snapshots agree.
	for n in 2:
		await succeed(alpha,"refill_tank",TANK,"","case 3 alpha fills the tank (%d)"%(n+1),[beta])
		var level:=48*(n+1)
		var t0:=Time.get_ticks_msec()
		var seen:=await all_see([alpha,beta],want_row(level,true),12.0)
		levels.append({"level":level,"ms_after_refill":Time.get_ticks_msec()-t0})
		expect(seen,"case 3 round %d: both snapshots show tower %d (alpha %s, beta %s)"%[n+1,level,row_of(alpha.tower()),row_of(beta.tower())])
		var tanks:Array=[alpha,beta].map(func(c):return int(c.session.snapshot.objects.get(World.key(TANK),{}).get("water",-1)))
		expect(tanks==[0,0],"case 3 round %d: the tank's leftover went into the tower (tank %s)"%[n+1,str(tanks)])
	expect(Industry.tower_report(alpha.session.snapshot,TOWER_KEY)==Industry.tower_report(beta.session.snapshot,TOWER_KEY),"case 3 tower_report identical on both clients")

	# 4. Owner toggles; both see it. Beta's toggle and removal are refused.
	var off:=await succeed(alpha,Industry.TOWER_ACTION,TOWER,"","case 4 alpha sets 只蓄水",[beta])
	expect(str(off.message)=="水塔已設為「只蓄水」","case 4 toggle message")
	expect(await all_see([alpha,beta],want_row(96,false),3.0),"case 4 both see 只蓄水 with 96 kept")
	await refuse(beta,Industry.TOWER_ACTION,TOWER,"",Industry.TOWER_NOT_OWNER,"case 4 beta toggles alpha's tower",[alpha])
	await refuse(beta,"remove",TOWER,"","只能拆除自己放置的物件","case 4 beta removes alpha's tower",[alpha])
	await refuse(beta,"move_object",TOWER,"%d,%d"%[TOWER.x,TOWER.y-1],"只能搬自己放置的家具","case 4 beta moves alpha's tower",[alpha])
	expect(await all_see([alpha,beta],want_row(96,false),1.0),"case 4 tower still 96 / 只蓄水 for both")

	# 5. Duplicate and replayed toggle messages.
	await settle([alpha,beta])
	var region:=str(alpha.session.snapshot.get("region_id",""))
	var epoch:=int(alpha.me().get("travel_epoch",0))
	var n0:=alpha.notices.size()
	var seq:int=int(alpha.session.counter)+1
	alpha.session.counter=seq
	alpha.session.request_action.rpc_id(1,seq,Industry.TOWER_ACTION,TOWER,"",region,epoch)
	alpha.session.request_action.rpc_id(1,seq,Industry.TOWER_ACTION,TOWER,"",region,epoch)
	await pause(0.8)
	await settle([alpha,beta])
	expect(alpha.notices.size()==n0+1 and alpha.notices[n0]==["水塔已設為「出水」",true],"case 5 the same sequence sent twice gets exactly one reply (%s)"%str(alpha.notices.slice(n0)))
	expect(await all_see([alpha,beta],want_row(96,true),2.0),"case 5 applied once: 出水 (not flipped back), both see it")
	var counts:=[alpha.notices.size(),beta.notices.size()]
	var before5:=marks_of([alpha,beta])
	alpha.session.request_action.rpc_id(1,int(off.sequence),Industry.TOWER_ACTION,TOWER,"",region,epoch)
	await pause(0.8)
	await settle([alpha,beta])
	expect(alpha.notices.size()==counts[0] and beta.notices.size()==counts[1],"case 5 re-sent old sequence %d gets no notice"%int(off.sequence))
	expect(marks_of([alpha,beta])==before5,"case 5 re-sent old sequence changes nothing on either end")
	var off2:=await succeed(alpha,Industry.TOWER_ACTION,TOWER,"","case 5 alpha's next normal toggle still works (只蓄水)",[beta])
	expect(str(off2.message)=="水塔已設為「只蓄水」" and await all_see([alpha,beta],want_row(96,false),3.0),"case 5 both see 只蓄水 again")
	await succeed(alpha,"build",GATE,Industry.GATE_KIND,"owner installs a downstream gate",[beta])
	await succeed(alpha,Industry.GATE_ACTION,GATE,"closed","owner closes the gate",[beta])
	var gate_key:=World.key(GATE)
	for client:Client in [alpha,beta]:
		var report:=Industry.zone_report(client.session.snapshot,gate_key)
		expect(report.ok and report.mode=="closed" and int(report.tanks)==1,"%s sees the closed gate on the same supply network"%client.label)
	await refuse(beta,Industry.GATE_ACTION,GATE,"open",Industry.GATE_NOT_OWNER,"visitor cannot reopen the owner's gate",[alpha])

	# 6. Normal shutdown -> exact save.
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 6 server shuts down with a final save")
	var disk=read_disk()
	if not expect(disk is Dictionary,"case 6 save parses"):return false
	expect(disk_valid(disk),"case 6 saved world passes SaveSchema")
	disk_tower_ok(disk,96,false,"case 6 save")
	expect(disk.objects.get(gate_key,{}).get("mode","")=="closed","Closed gate is saved")
	expect(int(disk.objects.get(World.key(TANK),{}).get("water",-1))==0 and int(disk.players[ALPHA].inventory.get(Industry.TOWER_KIT,0))==0,"case 6 save: tank 0, kit spent")

	# 7. Restart; same tower; late joiner sees it.
	var port2:=start_server()
	if not expect(port2>0,"case 7 restarted server hosts the same save"):return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	if not expect(joined(alpha) and joined(beta),"case 7 both rejoin"):return false
	expect(await all_see([alpha,beta],want_row(96,false),3.0),"case 7 restart: both see tower 96 / 只蓄水")
	gamma=await join("gamma",GAMMA,port2)
	if not expect(joined(gamma),"case 7 late joiner gamma joins"):return false
	await settle([alpha,beta,gamma])
	for client:Client in [alpha,beta,gamma]:
		expect(Industry.zone_report(client.session.snapshot,gate_key).mode=="closed","%s sees the saved gate mode after restart"%client.label)
	expect(row_of(gamma.tower())==want_row(96,false),"case 7 gamma sees the tower 96 / 只蓄水 (%s)"%row_of(gamma.tower()))
	expect(Industry.tower_report(gamma.session.snapshot,TOWER_KEY)==Industry.tower_report(alpha.session.snapshot,TOWER_KEY),"case 7 gamma's tower_report equals alpha's")
	private_check(gamma,[alpha,beta],"case 7")
	await refuse(beta,Industry.TOWER_ACTION,TOWER,"",Industry.TOWER_NOT_OWNER,"case 7 beta still cannot toggle after the restart",[alpha,gamma])
	var on:=await succeed(alpha,Industry.TOWER_ACTION,TOWER,"","case 7 alpha toggles after the restart (出水)",[beta,gamma])
	expect(str(on.message)=="水塔已設為「出水」" and await all_see([alpha,beta,gamma],want_row(96,true),3.0),"case 7 all three see 出水")
	await leave(gamma)
	gamma=null
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 7 restarted server shuts down cleanly")
	var after=read_disk()
	expect(disk_valid(after) and after.players.has(GAMMA),"case 7 final save valid, gamma recorded")
	disk_tower_ok(after,96,true,"case 7 final save")
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
