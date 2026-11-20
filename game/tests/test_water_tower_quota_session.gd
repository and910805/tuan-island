extends SceneTree
## 第 40 章「定量分區配水」tower_set (reserve / quota) two-client Session acceptance over a
## real dedicated server and real WebSocket clients (modelled on test_water_tower_session.gd).
##
## LEVEL: one machine, ONE Godot process. A dedicated server Session listens on a free
## 127.0.0.1 port (websocket transport); two client Sessions (alpha = owner, beta =
## visitor) and later a late joiner (gamma) join over loopback, each in its own branch
## with its own SceneMultiplayer. Clients only read their own received snapshots. The
## server World is never WRITTEN after seeding; it is only READ (objects of the tower /
## tank / sprinkler and Industry.tower_report on its state) in phases where the network
## is stable, to confirm the clients see exactly what the server holds. The on-disk save
## is read (file only) after shutdowns.
##
## SEEDED FIXTURE (disclosed): built offline in a World before the server starts and
## validated with SaveSchema. EARNED there through World.act: the canal repair, alpha's
## first 分水 memory, the plaque and the Lanyang revisit (same seed as
## test_water_tower_session.gd, unlocking the tower recipe), alpha's workbench at (50,22),
## the tower-kit craft, and the builds of the tank (49,22), the tower (48,22) and a small
## sprinkler (47,22) (placed disabled, as every new sprinkler is).
## WRITTEN DIRECTLY: repair materials, wood/stone for the bench, alpha's bag set to exactly
## plank 6 / copper_joint 2 / stone 6 / tank_kit 1 / sprinkler_kit 1 (all spent by the
## seed), every standing spot (Lanyang spots for the seed actions; home spots next to the
## bench/tank/tower/sprinkler for alpha and next to the tower for beta, region "home"),
## receipts cleared, and the tampered copies of the final save used for the four negative
## SaveSchema checks. NOTHING of the settings is pre-written: every reserve / quota value,
## the tank refill and the sprinkler toggle are sent by alpha's client over the network
## (World.act through Session). Tower refill, tower discharge and quota_day/quota_used
## come only from the server's real-time network rounds (one per 8 s of world time; world
## time starts at 0 and stays far below one world day = 1440 s, so quota_day is 0).
## Duplicate / replay: raw request_action RPCs (a) the same fresh sequence sent twice
## back-to-back (alpha's client counter advanced by the test) and (b) an already-used
## sequence re-sent later.
## Water math (no crops anywhere, so sprinklers never spend water; total stays 48):
##   reserve 24 + quota 8, tank refilled to 48, sprinkler off -> tower 24 / tank 24 (kept);
##   reserve 0 -> tower 48 / tank 0; sprinkler on -> tower sends min(12, 8) = 8 -> tower 40,
##   sprinkler 8, quota_used 8, and nothing more on later rounds; quota 16 keeps used 8 ->
##   next round sends 4 (sprinkler full) -> tower 36, sprinkler 12, quota_used 12.
## NOT covered: multiple processes, TLS, latency/loss, crash durability (normal shutdowns
## only), day rollover (rule test), lowering quota below the amount already sent.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Memory=preload("res://scripts/history_memory.gd")
const Industry=preload("res://scripts/industry.gd")
const KEY:="water-tower-quota-session"
const ALPHA:="tower-quota-alpha-token"
const BETA:="tower-quota-beta-token"
const GAMMA:="tower-quota-gamma-token"
const BENCH:=Vector2i(50,22)
const TANK:=Vector2i(49,22)
const TOWER:=Vector2i(48,22)
const SPRK:=Vector2i(47,22)
const TANK_KEY:="49,22"
const TOWER_KEY:="48,22"
const SPRK_KEY:="47,22"
const A_SPOT:=Vector2(32.5,24.5)
const B_SPOT:=Vector2(32.5,30.5)
const TOTAL:=48

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
	func obj(key:String)->Dictionary:
		var objs=session.snapshot.get("objects",{})
		if not objs is Dictionary:return {}
		var o=objs.get(key,{})
		return o if o is Dictionary else {}
	func tower()->Dictionary:
		return obj(TOWER_KEY)
	func water_of(key:String)->int:
		return int(obj(key).get("water",-1))

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
var samples:=0
var violations:Array=[]
var expected_total:=-1
var last_tower:={}
var rounds_seen:=[]

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
	print("WATER_TOWER_QUOTA_SESSION watchdog fired before completion")
	print("WATER_TOWER_QUOTA_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("WATER_TOWER_QUOTA_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("WATER_TOWER_QUOTA_SESSION rounds seen %s"%str(rounds_seen))
	print("WATER_TOWER_QUOTA_SESSION invariant samples=%d violations=%s"%[samples,str(violations.slice(0,5))])
	print("WATER_TOWER_QUOTA_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("WATER_TOWER_QUOTA_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

func seed_act(w:World,token:String,action:String,p:Vector2i,extra:String="")->bool:
	serial+=1
	var r:=w.act(token,"seed-%d"%serial,action,p,extra)
	if not r.ok:print("WATER_TOWER_QUOTA_SESSION seed action %s %s %s refused: %s"%[action,str(p),extra,str(r.message)])
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

## Standable home tiles within 3.0 of every target cell centre (device cells excluded).
func home_spot(w:World,targets:Array,taken:Array)->Vector2:
	for y in range(20,32):
		for x in range(42,56):
			var tile:=Vector2i(x,y)
			if tile in [BENCH,TANK,TOWER,SPRK] or tile in taken:continue
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
	# Home: alpha's bench, the tower kit, then tank + tower + sprinkler (all through World.act).
	var a_spot:=home_spot(w,[BENCH,TANK,TOWER,SPRK],[])
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
	inv["sprinkler_kit"]=1
	a_spot=home_spot(w,[BENCH,TANK,TOWER,SPRK],[])
	if a_spot.x<0:return false
	place(w,ALPHA,"home",a_spot)
	if not seed_act(w,ALPHA,"craft",BENCH,Industry.TOWER_KIT):return false
	if not seed_act(w,ALPHA,"build",TANK,"water_tank"):return false
	if not seed_act(w,ALPHA,"build",TOWER,Industry.TOWER_KIND):return false
	if not seed_act(w,ALPHA,"build",SPRK,"sprinkler"):return false
	for item in inv.keys():
		if int(inv[item])!=0:
			print("WATER_TOWER_QUOTA_SESSION seed bag not spent: %s"%str(inv))
			return false
	var b_spot:=home_spot(w,[TOWER],[Vector2i(floori(a_spot.x),floori(a_spot.y))])
	if b_spot.x<0:return false
	place(w,BETA,"home",b_spot)
	home_spots={"alpha":a_spot,"beta":b_spot}
	for t in [ALPHA,BETA]:w.state.players[t]["receipts"]={}
	w.active_tokens.clear()
	w.save_path=path
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or float(parsed.time)!=0.0:return false
	var saved_tower=parsed.objects.get(TOWER_KEY,null)
	if not saved_tower is Dictionary or str(saved_tower.get("type"))!=Industry.TOWER_KIND:return false
	for field in ["reserve","quota","quota_day","quota_used"]:
		if saved_tower.has(field):return false
	var saved_sprinkler=parsed.objects.get(SPRK_KEY,null)
	if not saved_sprinkler is Dictionary or saved_sprinkler.get("enabled")!=false:return false
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

## Every frame of every wait also samples the invariants on each live client snapshot.
func wait_until(condition:Callable,seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<deadline:
		sample()
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

## Waits until the client's world clock has moved past at least one more network round.
func wait_round(c:Client)->bool:
	var t0:=float(c.session.snapshot.get("time",-1.0))
	return await wait_until(func():return float(c.session.snapshot.get("time",-1.0))>=t0+Industry.INTERVAL+0.5,12.0)

# ---------------------------------------------------------------- helpers --

static func canon(d:Variant)->Dictionary:
	var out:={}
	if not d is Dictionary:return {"<invalid>":-1}
	for item in d:
		if int(d[item])!=0:out[str(item)]=int(d[item])
	return out

static func text(d:Variant)->String:
	return JSON.stringify(d,"",true)

## An optional numeric field as text: "absent", its integer value, or "bad:<value>".
static func opt(o:Dictionary,field:String)->String:
	if not o.has(field):return "absent"
	var v:Variant=o[field]
	if typeof(v) in [TYPE_INT,TYPE_FLOAT] and float(v)==float(int(v)):return str(int(v))
	return "bad:"+str(v)

static func fields_of(o:Dictionary)->String:
	if o.is_empty():return "none"
	return text({"water":int(o.get("water",-1)),"enabled":o.get("enabled"),"reserve":opt(o,"reserve"),"quota":opt(o,"quota"),"quota_day":opt(o,"quota_day"),"quota_used":opt(o,"quota_used")})

## Public tower row as a client sees it (owner is the public id, never the token).
static func row_of(o:Dictionary)->String:
	if o.is_empty():return "none"
	return text({"type":o.get("type"),"owner":o.get("owner"),"items":o.get("items"),"fields":fields_of(o)})

static func want_row(water:int,reserve:int,quota:int,used:int)->String:
	var f:={"water":water,"enabled":true,"reserve":str(reserve) if reserve>0 else "absent","quota":str(quota) if quota>0 else "absent",
		"quota_day":"0" if quota>0 else "absent","quota_used":str(used) if quota>0 else "absent"}
	return text({"type":"water_tower","owner":ALPHA.sha256_text().left(16),"items":{},"fields":text(f)})

static func net_text(tank:int,sprinkler:int,on:bool)->String:
	return text({"tank":tank,"sprinkler":sprinkler,"sprinkler_on":on})

static func net_of(c:Client)->String:
	return net_text(c.water_of(TANK_KEY),c.water_of(SPRK_KEY),c.obj(SPRK_KEY).get("enabled")==true)

func marks_of(clients:Array)->Array:
	return clients.map(func(x):return [text(canon(x.bag())),row_of(x.tower()),net_of(x)])

func refuse(c:Client,action:String,p:Vector2i,extra:String,message:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var marks:=marks_of(everyone)
	var r:=await act(c,action,p,extra)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	expect(marks_of(everyone)==marks,"%s: bags, tower and network unchanged in every watching snapshot"%label)

func succeed(c:Client,action:String,p:Vector2i,extra:String,label:String,watchers:Array)->Dictionary:
	var r:=await act(c,action,p,extra)
	expect(r.replied and r.ok,"%s: ok (got ok=%s '%s')"%[label,str(r.ok),str(r.message)])
	await settle([c]+watchers)
	return r

## Owner setting through the network: exact success message, then every watcher sees the row.
## `alt` is the only other acceptable row: the state one network round later, for settings
## made while a round can still move water (a round may land before the snapshot is read).
func setting(extra:String,label:String,watchers:Array,row:String,alt:String="")->Dictionary:
	var r:=await succeed(alpha,Industry.TOWER_SET_ACTION,TOWER,extra,label,watchers)
	expect(str(r.message)==Industry.tower_set_message(extra),"%s: message '%s' (got '%s')"%[label,Industry.tower_set_message(extra),str(r.message)])
	var everyone:Array=[alpha]+watchers
	var seen:=await wait_until(func():
		for c:Client in everyone:
			var got:=row_of(c.tower())
			if got!=row and (alt.is_empty() or got!=alt):return false
		return true,3.0)
	expect(seen,"%s: every client sees %s%s (%s)"%[label,row,("" if alt.is_empty() else " or "+alt),str(everyone.map(func(c):return row_of(c.tower())))])
	return r

func all_see(clients:Array,row:String,net:String,seconds:float)->bool:
	return await wait_until(func():
		for c:Client in clients:
			if row_of(c.tower())!=row or net_of(c)!=net:return false
		return true,seconds)

func seen_text(clients:Array)->String:
	return str(clients.map(func(c):return "%s %s %s"%[c.label,row_of(c.tower()),net_of(c)]))

func private_check(c:Client,others:Array,label:String)->void:
	var dump:=JSON.stringify(c.session.snapshot)
	var leaked:=false
	for o:Client in others+[c]:
		if dump.contains(o.token):leaked=true
	expect(not leaked,"%s: %s's snapshot contains no raw token"%[label,c.label])

static func key_set(snapshot:Dictionary)->Array:
	var keys:Array=[]
	for k in snapshot:keys.append(str(k))
	keys.sort()
	return keys

## Exact client-side object key set of the tower for the given settings.
static func tower_keys(reserve:int,quota:int)->Array:
	var keys:Array=["enabled","items","owner","type","water"]
	if reserve>0:keys.append("reserve")
	if quota>0:keys.append_array(["quota","quota_day","quota_used"])
	keys.sort()
	return keys

static func sorted_keys(o:Dictionary)->Array:
	var keys:Array=[]
	for k in o:keys.append(str(k))
	keys.sort()
	return keys

## tower_report on every client snapshot (and on the server state) agrees with the expectation.
func reports_agree(clients:Array,water:int,reserve:int,quota:int,used:int,label:String)->void:
	var left:int=maxi(0,quota-used) if quota>0 else -1
	var reports:Array=[]
	for c:Client in clients:
		var rep:=Industry.tower_report(c.session.snapshot,TOWER_KEY)
		reports.append(rep)
		expect(rep.ok==true and int(rep.water)==water and int(rep.reserve)==reserve and int(rep.quota)==quota and int(rep.quota_used)==used and int(rep.quota_left)==left and rep.enabled==true,
			"%s: %s tower_report water %d reserve %d quota %d used %d left %d (%s)"%[label,c.label,water,reserve,quota,used,left,str(rep)])
		expect(sorted_keys(c.tower())==tower_keys(reserve,quota),"%s: %s tower object keys %s (got %s)"%[label,c.label,str(tower_keys(reserve,quota)),str(sorted_keys(c.tower()))])
	var same:=true
	for rep in reports:
		if rep!=reports[0]:same=false
	expect(same,"%s: tower_report identical on every client"%label)
	if server!=null and is_instance_valid(server) and server.world!=null:
		var server_rep:=Industry.tower_report(server.world.state,TOWER_KEY)
		expect(server_rep==reports[0],"%s: client tower_report equals the report on the server state (%s)"%[label,str(server_rep)])

func server_obj(key:String)->Dictionary:
	if server==null or not is_instance_valid(server) or server.world==null:return {}
	var objs=server.world.state.get("objects",{})
	if not objs is Dictionary:return {}
	var o=objs.get(key,{})
	return o if o is Dictionary else {}

## Stable phase: every client's tower fields, tank and sprinkler equal the server state.
func server_matches(clients:Array,label:String)->void:
	var st:=server_obj(TOWER_KEY)
	var want_net:=net_text(int(server_obj(TANK_KEY).get("water",-1)),int(server_obj(SPRK_KEY).get("water",-1)),server_obj(SPRK_KEY).get("enabled")==true)
	for c:Client in clients:
		expect(not st.is_empty() and fields_of(c.tower())==fields_of(st) and net_of(c)==want_net,"%s: %s sees exactly the server's tower/tank/sprinkler (server %s %s, client %s %s)"%[label,c.label,fields_of(st),want_net,fields_of(c.tower()),net_of(c)])

func note(message:String)->void:
	if violations.size()<20:violations.append(message)

## Invariants on every live client snapshot, every frame of every wait.
func sample()->void:
	for c in [alpha,beta,gamma]:
		if c==null or not is_instance_valid(c.session) or c.session.shutting_down:continue
		var o:Dictionary=c.tower()
		if o.is_empty():continue
		samples+=1
		var has_q:=o.has("quota")
		if has_q!=o.has("quota_day") or has_q!=o.has("quota_used"):note("%s: quota fields not together %s"%[c.label,row_of(o)])
		if has_q and int(o.get("quota_used",0))>int(o.get("quota",0)):note("%s: quota_used above quota %s"%[c.label,row_of(o)])
		var water:int=int(o.get("water",0))
		var tank:int=int(c.water_of(TANK_KEY))
		var total:int=tank+water+int(c.water_of(SPRK_KEY))
		if expected_total>=0 and total!=expected_total:note("%s: water total %d != %d (%s %s)"%[c.label,total,expected_total,row_of(o),net_of(c)])
		var prev:=int(last_tower.get(c.label,water))
		var reserve:=Industry.tower_reserve(o)
		if water>prev and reserve>0 and tank<reserve:note("%s: tower gained %d while the tank fell to %d below reserve %d"%[c.label,water-prev,tank,reserve])
		last_tower[c.label]=water

func read_disk()->Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(save_path))

func disk_valid(disk:Variant)->bool:
	return disk is Dictionary and Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

static func disk_num(o:Dictionary,field:String,value:int)->bool:
	var v:Variant=o.get(field)
	return typeof(v) in [TYPE_INT,TYPE_FLOAT] and float(v)==float(value)

## Field-by-field check of the saved tower object (and the tank / sprinkler beside it).
func disk_tower_ok(disk:Variant,water:int,reserve:int,quota:int,used:int,label:String)->void:
	var o=disk.get("objects",{}).get(TOWER_KEY,null) if disk is Dictionary else null
	if not expect(o is Dictionary,"%s: saved tower object present"%label):return
	expect(sorted_keys(o)==tower_keys(reserve,quota),"%s: saved tower keys exactly %s (got %s)"%[label,str(tower_keys(reserve,quota)),str(sorted_keys(o))])
	expect(str(o.get("type"))=="water_tower" and str(o.get("owner"))==ALPHA and o.get("enabled")==true,"%s: type water_tower, owner alpha (raw token on disk), 出水"%label)
	expect(disk_num(o,"water",water),"%s: water %d (got %s)"%[label,water,str(o.get("water"))])
	if reserve>0:expect(disk_num(o,"reserve",reserve),"%s: reserve %d (got %s)"%[label,reserve,str(o.get("reserve"))])
	if quota>0:
		expect(disk_num(o,"quota",quota) and disk_num(o,"quota_day",0) and disk_num(o,"quota_used",used),"%s: quota %d / quota_day 0 / quota_used %d (got %s / %s / %s)"%[label,quota,used,str(o.get("quota")),str(o.get("quota_day")),str(o.get("quota_used"))])
	var tank=disk.objects.get(TANK_KEY,{})
	var sprk=disk.objects.get(SPRK_KEY,{})
	expect(tank is Dictionary and disk_num(tank,"water",0) and sprk is Dictionary and disk_num(sprk,"water",12) and sprk.get("enabled")==true,"%s: tank 0, sprinkler 12 and on"%label)

## Tampered copies of a valid save (written directly) must fail SaveSchema.
func tamper_checks(disk:Dictionary,label:String)->void:
	var cases:={"quota removed but quota_day/quota_used kept":func(o:Dictionary):o.erase("quota"),
		"reserve 7 (not an option)":func(o:Dictionary):o["reserve"]=7,
		"quota_used 25 (above 24)":func(o:Dictionary):o["quota_used"]=25,
		"quota_used missing":func(o:Dictionary):o.erase("quota_used")}
	for case_name in cases:
		var copy:Dictionary=disk.duplicate(true)
		var o:Dictionary=copy.objects[TOWER_KEY]
		(cases[case_name] as Callable).call(o)
		expect(not disk_valid(copy),"%s: SaveSchema rejects a save with %s"%[label,str(case_name)])

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("water-tower-quota-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"SEEDED FIXTURE (revisit, bench, kit craft, tank/tower/sprinkler builds earned offline; materials and spots written; no settings) accepted by SaveSchema"):return false
	print("WATER_TOWER_QUOTA_SESSION seed spots %s"%str(home_spots))
	var port:=start_server()
	if not expect(port>0,"server Session hosts on 127.0.0.1 (websocket)"):return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	if not expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback"):return false
	expect(server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer,"server and clients use WebSocketMultiplayerPeer")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World")
	await settle([alpha,beta])
	print("WATER_TOWER_QUOTA_SESSION_LABEL machine=single process=single transport=websocket loopback=127.0.0.1:%d clients=2(+late joiner) fixture=SEEDED(revisit+bench+kit+tank/tower/sprinkler earned offline; materials, spots written; no settings) shutdown=normal-only"%port)

	# 1. Before any setting: plain tower, no new fields, report defaults.
	expected_total=0
	expect(await all_see([alpha,beta],want_row(0,0,0,0),net_text(0,0,false),3.0),"case 1 both see the plain tower (water 0, no reserve/quota), tank 0, sprinkler 0 off %s"%seen_text([alpha,beta]))
	reports_agree([alpha,beta],0,0,0,0,"case 1")
	expect(float(alpha.session.snapshot.get("time",-1.0))>=0.0 and float(alpha.session.snapshot.get("time",-1.0))<Industry.TOWER_DAY,"case 1 world time is on day 0")
	var keys_alpha:=key_set(alpha.session.snapshot)
	var keys_beta:=key_set(beta.session.snapshot)
	for c:Client in [alpha,beta]:private_check(c,[beta if c==alpha else alpha],"case 1")

	# 2. Owner sets reserve 24 and quota 8 over the network.
	# The reserve:24 request's sequence is re-sent in case 4 (replay).
	var first_reserve:=await setting("reserve:24","case 2 alpha sets reserve 24",[beta],want_row(0,24,0,0))
	reports_agree([alpha,beta],0,24,0,0,"case 2 after reserve")
	await setting("quota:8","case 2 alpha sets quota 8",[beta],want_row(0,24,8,0))
	reports_agree([alpha,beta],0,24,8,0,"case 2 after quota")
	server_matches([alpha,beta],"case 2")

	# 3. Refusals: visitor, wrong cell, bad extras, same setting. World unchanged everywhere.
	await refuse(beta,Industry.TOWER_SET_ACTION,TOWER,"reserve:12",Industry.TOWER_NOT_OWNER,"case 3 beta sets reserve on alpha's tower",[alpha])
	await refuse(beta,Industry.TOWER_SET_ACTION,TOWER,"quota:4",Industry.TOWER_NOT_OWNER,"case 3 beta sets quota on alpha's tower",[alpha])
	await refuse(beta,Industry.TOWER_SET_ACTION,TOWER,"quota:0",Industry.TOWER_NOT_OWNER,"case 3 beta clears alpha's quota",[alpha])
	await refuse(alpha,Industry.TOWER_SET_ACTION,TANK,"reserve:12",Industry.TOWER_NOT_OWNER,"case 3 alpha tower_set on her tank (not a tower)",[beta])
	await refuse(alpha,Industry.TOWER_SET_ACTION,SPRK,"quota:4",Industry.TOWER_NOT_OWNER,"case 3 alpha tower_set on her sprinkler (not a tower)",[beta])
	for bad in ["quota:04","quota:-4","reserve:12:1","water:5","","reserve:7","quota:5","reserve:+12","quota:","reserve: 12"]:
		await refuse(alpha,Industry.TOWER_SET_ACTION,TOWER,bad,Industry.TOWER_BAD_SETTING,"case 3 alpha bad extra '%s'"%bad,[beta])
	await refuse(alpha,Industry.TOWER_SET_ACTION,TOWER,"reserve:24",Industry.TOWER_SAME_SETTING,"case 3 alpha same reserve 24",[beta])
	await refuse(alpha,Industry.TOWER_SET_ACTION,TOWER,"quota:8",Industry.TOWER_SAME_SETTING,"case 3 alpha same quota 8",[beta])
	expect(await all_see([alpha,beta],want_row(0,24,8,0),net_text(0,0,false),1.0),"case 3 tower still reserve 24 / quota 8 for both")

	# 4. Duplicate and replayed tower_set messages.
	await settle([alpha,beta])
	var region:=str(alpha.session.snapshot.get("region_id",""))
	var epoch:=int(alpha.me().get("travel_epoch",0))
	var n0:=alpha.notices.size()
	var b0:=beta.notices.size()
	var seq:int=int(alpha.session.counter)+1
	alpha.session.counter=seq
	alpha.session.request_action.rpc_id(1,seq,Industry.TOWER_SET_ACTION,TOWER,"reserve:36",region,epoch)
	alpha.session.request_action.rpc_id(1,seq,Industry.TOWER_SET_ACTION,TOWER,"reserve:36",region,epoch)
	await pause(0.8)
	await settle([alpha,beta])
	expect(alpha.notices.size()==n0+1 and alpha.notices[n0]==[Industry.tower_set_message("reserve:36"),true],"case 4 the same sequence sent twice gets exactly one reply (%s)"%str(alpha.notices.slice(n0)))
	expect(beta.notices.size()==b0,"case 4 beta gets no notice from alpha's duplicate")
	expect(await all_see([alpha,beta],want_row(0,36,8,0),net_text(0,0,false),2.0),"case 4 applied once: reserve 36, both see it %s"%seen_text([alpha,beta]))
	var counts:=[alpha.notices.size(),beta.notices.size()]
	var before4:=marks_of([alpha,beta])
	alpha.session.request_action.rpc_id(1,int(first_reserve.sequence),Industry.TOWER_SET_ACTION,TOWER,"reserve:24",region,epoch)
	await pause(0.8)
	await settle([alpha,beta])
	expect(alpha.notices.size()==counts[0] and beta.notices.size()==counts[1],"case 4 re-sent old reserve:24 sequence %d gets no notice"%int(first_reserve.sequence))
	expect(marks_of([alpha,beta])==before4,"case 4 re-sent old sequence changes nothing on either end (reserve stays 36)")
	await setting("reserve:24","case 4 alpha's next normal setting still works (reserve 24)",[beta],want_row(0,24,8,0))
	reports_agree([alpha,beta],0,24,8,0,"case 4")

	# 5. Real server rounds. (a) Tank refilled to 48 with reserve 24: the tower takes 24 only.
	expected_total=-1
	await succeed(alpha,"refill_tank",TANK,"","case 5a alpha fills the tank",[beta])
	expected_total=TOTAL
	var t0:=Time.get_ticks_msec()
	var seen:=await all_see([alpha,beta],want_row(24,24,8,0),net_text(24,0,false),12.0)
	rounds_seen.append({"step":"reserve 24 refill","ms":Time.get_ticks_msec()-t0})
	expect(seen,"case 5a both see tower 24 / tank 24 (reserve kept) %s"%seen_text([alpha,beta]))
	expect(await wait_round(alpha),"case 5a another network round passed")
	expect(await all_see([alpha,beta],want_row(24,24,8,0),net_text(24,0,false),1.0),"case 5a after another round the tank still holds the reserve 24 %s"%seen_text([alpha,beta]))
	reports_agree([alpha,beta],24,24,8,0,"case 5a")
	server_matches([alpha,beta],"case 5a")

	# (b) reserve 0 removes the field; next round the tower takes the rest.
	await setting("reserve:0","case 5b alpha sets 不保留桶水",[beta],want_row(24,0,8,0),want_row(48,0,8,0))
	expect(not alpha.tower().has("reserve") and not beta.tower().has("reserve"),"case 5b reserve field removed on both ends")
	t0=Time.get_ticks_msec()
	seen=await all_see([alpha,beta],want_row(48,0,8,0),net_text(0,0,false),12.0)
	rounds_seen.append({"step":"reserve 0","ms":Time.get_ticks_msec()-t0})
	expect(seen,"case 5b both see tower 48 / tank 0 %s"%seen_text([alpha,beta]))
	reports_agree([alpha,beta],48,0,8,0,"case 5b")
	server_matches([alpha,beta],"case 5b")

	# (c) Sprinkler on: the tower sends exactly the quota 8 and then stops for the day.
	await succeed(alpha,"toggle_sprinkler",SPRK,"","case 5c alpha turns the sprinkler on",[beta])
	t0=Time.get_ticks_msec()
	seen=await all_see([alpha,beta],want_row(40,0,8,8),net_text(0,8,true),12.0)
	rounds_seen.append({"step":"quota 8 discharge","ms":Time.get_ticks_msec()-t0})
	expect(seen,"case 5c both see tower 40 / sprinkler 8 / quota_used 8 %s"%seen_text([alpha,beta]))
	expect(await wait_round(alpha),"case 5c another network round passed")
	expect(await all_see([alpha,beta],want_row(40,0,8,8),net_text(0,8,true),1.0),"case 5c the quota is spent: no more water sent on the next round %s"%seen_text([alpha,beta]))
	reports_agree([alpha,beta],40,0,8,8,"case 5c")
	server_matches([alpha,beta],"case 5c")
	for c:Client in [alpha,beta]:
		var o:=c.tower()
		expect(int(o.get("quota_used",-1))<=int(o.get("quota",0)) and int(o.get("quota_day",-1))==0,"case 5c %s quota_used %s <= quota %s on day 0"%[c.label,opt(o,"quota_used"),opt(o,"quota")])

	# (d) Raising the quota the same day keeps what was sent; the next round tops the sprinkler up.
	# Before the next round the tower shows used 8 (kept); if a round already landed it shows
	# used 12 (8 kept + 4 sent; a reset to 0 would have given 4).
	await setting("quota:16","case 5d alpha raises the quota to 16",[beta],want_row(40,0,16,8),want_row(36,0,16,12))
	for c:Client in [alpha,beta]:
		var o:=c.tower()
		expect(opt(o,"quota")=="16" and opt(o,"quota_day")=="0" and opt(o,"quota_used") in ["8","12"],"case 5d %s: same-day raise keeps the 8 already sent (quota %s used %s)"%[c.label,opt(o,"quota"),opt(o,"quota_used")])
	t0=Time.get_ticks_msec()
	seen=await all_see([alpha,beta],want_row(36,0,16,12),net_text(0,12,true),12.0)
	rounds_seen.append({"step":"quota 16 discharge","ms":Time.get_ticks_msec()-t0})
	expect(seen,"case 5d both see tower 36 / sprinkler 12 / quota_used 12 %s"%seen_text([alpha,beta]))
	reports_agree([alpha,beta],36,0,16,12,"case 5d")
	server_matches([alpha,beta],"case 5d")
	await setting("reserve:24","case 5d alpha sets reserve 24 again",[beta],want_row(36,24,16,12))
	reports_agree([alpha,beta],36,24,16,12,"case 5d final")
	await refuse(beta,Industry.TOWER_SET_ACTION,TOWER,"quota:24",Industry.TOWER_NOT_OWNER,"case 5d beta still cannot change the quota",[alpha])
	expect(key_set(alpha.session.snapshot)==keys_alpha and key_set(beta.session.snapshot)==keys_beta,"case 5 snapshot top-level keys unchanged by the settings (alpha %s)"%str(key_set(alpha.session.snapshot)))
	for c:Client in [alpha,beta]:private_check(c,[beta if c==alpha else alpha],"case 5")

	# 6. Normal shutdown -> exact save.
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 6 server shuts down with a final save")
	var disk=read_disk()
	if not expect(disk is Dictionary,"case 6 save parses"):return false
	expect(disk_valid(disk),"case 6 saved world passes SaveSchema")
	disk_tower_ok(disk,36,24,16,12,"case 6 save")
	expect(float(disk.get("time",-1.0))<Industry.TOWER_DAY,"case 6 saved time still on day 0")
	tamper_checks(disk,"case 6")

	# 7. Restart; same settings; late joiner sees them; quota 0 -> back starts from 0.
	var port2:=start_server()
	if not expect(port2>0,"case 7 restarted server hosts the same save"):return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	if not expect(joined(alpha) and joined(beta),"case 7 both rejoin"):return false
	expect(await all_see([alpha,beta],want_row(36,24,16,12),net_text(0,12,true),3.0),"case 7 restart: both see reserve 24 / quota 16 / used 12 / water 36 %s"%seen_text([alpha,beta]))
	gamma=await join("gamma",GAMMA,port2)
	if not expect(joined(gamma),"case 7 late joiner gamma joins"):return false
	await settle([alpha,beta,gamma])
	expect(row_of(gamma.tower())==want_row(36,24,16,12) and net_of(gamma)==net_text(0,12,true),"case 7 gamma sees the same tower and network %s"%seen_text([gamma]))
	reports_agree([alpha,beta,gamma],36,24,16,12,"case 7 restart")
	server_matches([alpha,beta,gamma],"case 7 restart")
	expect(key_set(alpha.session.snapshot)==keys_alpha and key_set(gamma.session.snapshot)==keys_alpha,"case 7 snapshot top-level keys unchanged after the restart (alpha and gamma)")
	private_check(gamma,[alpha,beta],"case 7")
	await refuse(beta,Industry.TOWER_SET_ACTION,TOWER,"reserve:0",Industry.TOWER_NOT_OWNER,"case 7 beta still cannot change settings after the restart",[alpha,gamma])
	if gamma_near_tower():
		await refuse(gamma,Industry.TOWER_SET_ACTION,TOWER,"quota:0",Industry.TOWER_NOT_OWNER,"case 7 gamma cannot change alpha's settings",[alpha,beta])
	await setting("quota:0","case 7 alpha sets 每日配水不限",[beta,gamma],want_row(36,24,0,0))
	for c:Client in [alpha,beta,gamma]:
		var o:=c.tower()
		expect(not o.has("quota") and not o.has("quota_day") and not o.has("quota_used"),"case 7 %s: quota, quota_day and quota_used removed"%c.label)
	reports_agree([alpha,beta,gamma],36,24,0,0,"case 7 unlimited")
	await setting("quota:16","case 7 alpha sets quota 16 again (counts from 0)",[beta,gamma],want_row(36,24,16,0))
	reports_agree([alpha,beta,gamma],36,24,16,0,"case 7 quota back")
	server_matches([alpha,beta,gamma],"case 7 final")
	await leave(gamma)
	gamma=null
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 7 restarted server shuts down cleanly")
	var after=read_disk()
	expect(disk_valid(after) and after.players.has(GAMMA),"case 7 final save valid, gamma recorded")
	disk_tower_ok(after,36,24,16,0,"case 7 final save")

	# 8. Invariants sampled on every frame of every wait (all clients).
	expect(samples>200,"case 8 invariants sampled on many client snapshots (%d)"%samples)
	expect(violations.is_empty(),"case 8 no invariant violation: quota fields together, quota_used <= quota, water total 48 after the refill, no tower gain below the tank reserve (%s)"%str(violations))
	return true

## Gamma joins at the server's spawn; only test its refusal when the World's reach would not
## refuse it first for distance (the refusal message must be the owner message).
func gamma_near_tower()->bool:
	var me:=gamma.me()
	if me.is_empty():return false
	return Vector2(float(me.get("x",-99.0)),float(me.get("y",-99.0))).distance_to(Vector2(TOWER)+Vector2(0.5,0.5))<=3.0

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
	return

func remove_folder()->bool:
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):return false
	var dir:=DirAccess.open(folder)
	if dir==null:return false
	for file in dir.get_files():
		if DirAccess.remove_absolute(folder.path_join(file))!=OK:return false
	return DirAccess.remove_absolute(folder)==OK and not DirAccess.dir_exists_absolute(folder)
