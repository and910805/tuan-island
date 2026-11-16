extends SceneTree
## 第 40 章北門合作鹽田「儲滷槽」two-client Session acceptance over a real dedicated server
## and real WebSocket clients (modelled on test_salt_revisit_session.gd).
##
## LEVEL: one machine, ONE Godot process. A dedicated server Session listens on a free
## 127.0.0.1 port (websocket transport); two client Sessions (alpha and beta, both standing at
## the brine tank in 北門) and later a late joiner (gamma, at home) join over loopback, each in
## its own branch with its own SceneMultiplayer. Clients only read their own received
## snapshots. The server World is never written after seeding; it is read once (after both
## clients left, so the world clock is paused) to compare with the on-disk save.
##
## SEEDED FIXTURE (disclosed): built offline in a World before the server starts and validated
## with SaveSchema. EARNED there through World.act / World.step: both players' salt letter at
## 小栗's stall, the transit trip home → 田尾 → 北門, salt_intro, the three gate repairs (alpha
## donates), each player's first hand rake on a public pan, alpha's salt_claim of lot 0 and
## salt_install of her wheel, and the wheel filling alpha's two pans (one World.step of 290 s:
## both pans brine with ~290 progress, day 1 sunny). WRITTEN directly: the chapter 1/2/3 story
## fixture (as test_salt_pan_world), the gate materials, the two salt_wheel_kit (alpha's, used
## offline, and beta's, installed over the network), the standing spots (both at
## SaltBrine.TANK_STAND), receipts cleared. No salt_brine key is preset; beta owns no lot.
## Everything after the seed goes through client Sessions over the network: beta is refused
## (NO_UNIT), WALKS (input_direction) from the tank to lot 2, claims it and installs her wheel,
## walks back and pours the brine alpha stored. World time only advances by the server's
## real-time ticks (≈1 game second per real second while someone is online), so progress
## values are checked in ranges that hold for well over a minute of drift.
## Replay: the raw request_action RPC re-sent with alpha's already-used store sequence number
## (and a different side); Session drops it.
## NOT covered: multiple processes, TLS, latency/loss, crash durability (normal shutdowns
## only), rain and the exact time model (rule level, test_salt_brine.gd).
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const SB=preload("res://scripts/salt_brine.gd")
const Salt=preload("res://scripts/salt_pan.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const Transit=preload("res://scripts/transit.gd")
const KEY:="salt-brine-session"
const ALPHA:="saltbrine-session-alpha-token"
const BETA:="saltbrine-session-beta-token"
const GAMMA:="saltbrine-session-gamma-token"
const STALL:=Vector2i(43,29)
const BETA_LOT:=2
const CLAIM_CELL:=Vector2i(33,15) # bottom-left cell of pan 4 (lot 2, west pan)
const WHEEL_CELL:=Vector2i(32,14) # east cell of lot 2's wheel socket
const ROW_Y:=18 # walking corridor between the lot rows
const LOT_X:=32 # column west of lot 2's pans

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
	func brine()->Variant:
		return session.snapshot.get("salt_brine",null)
	func pans()->Array:
		var salt=session.snapshot.get("salt_pan",{})
		var list=salt.get("pans",[]) if salt is Dictionary else []
		return list if list is Array else []
	func pan(i:int)->Dictionary:
		var list:=pans()
		return list[i] if i<list.size() and list[i] is Dictionary else {}
	func pos()->Vector2:
		var m:=me()
		return Vector2(float(m.get("x",-99.0)),float(m.get("y",-99.0)))

var checks:=0
var failures:=0
var serial:=0
var folder:=""
var save_path:=""
var seed_time:=0.0
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
	create_timer(115.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("SALT_BRINE_SESSION watchdog fired before completion")
	print("SALT_BRINE_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("SALT_BRINE_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("SALT_BRINE_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("SALT_BRINE_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

func seed_act(w:World,token:String,action:String,p:Vector2i,extra:String="")->bool:
	serial+=1
	var r:Dictionary=w.act(token,"seed-%d"%serial,action,p,extra)
	if not r.ok:push_error("seed step %s failed: %s"%[action,str(r.message)])
	return bool(r.ok)

func place(w:World,token:String,region:String,at:Vector2)->void:
	var p:Dictionary=w.state.players[token]
	p["region"]=region
	p["x"]=at.x
	p["y"]=at.y

func bag_of(w:World,token:String)->Dictionary:
	return w.state.players[token].inventory

## FIXTURE (as test_salt_pan_world): chapter 1, chapter 2 tea comparison, chapter 3 flowers.
func story_fixture(w:World,token:String)->void:
	w.state.picnic=true
	w.state.board=true
	w.state.chapter_one.shipped=true
	w.state.chapter_one.watered=true
	var tea:Dictionary=Tea.FRESH.duplicate(true)
	tea.intro=true;tea.potter=true;tea.reused=true;tea.reuse_count=1
	tea.trials={"jar":true,"fiber":true};tea.tea_discussed=true;tea.comparison_complete=true
	w.state.tea_ceramics.players[token]=tea
	var a:Dictionary=Flower.FRESH.duplicate(true)
	a.letter=true;a.intro=true;a.shipped=true;a.complete=true
	for kind in Flower.FLOWERS:
		a.planted[kind]=true;a.harvested[kind]=2;a.saved[kind]=true
	w.state.flower_nursery.players[token]=a
	w.state.players[token].travel_book.visited[Flower.REGION]=true
	if not w.state.flower_nursery.get("garden",{}).get("complete",false):
		w.state.flower_nursery.garden={"given":{"blue_dye":4,"orange_blossom":4,"chime_herb":2},"contributors":{token:10},"complete":true,"completed_at":0.0}

func stand(w:World,token:String,cell:Vector2i)->bool:
	var region:String=w.player_region(token)
	w.switch_region(region)
	var best:=Vector2.ZERO
	var best_d:=INF
	var centre:=Vector2(cell)+Vector2(0.5,0.5)
	for dy in range(-3,4):
		for dx in range(-3,4):
			var pos:=Vector2(cell.x+dx,cell.y+dy)+Vector2(0.5,0.5)
			var d:=pos.distance_to(centre)
			if d<0.9 or d>2.9:continue
			if w.can_stand(pos) and d<best_d:
				best=pos
				best_d=d
	w.switch_region("home")
	if best_d==INF:return false
	w.state.players[token].x=best.x
	w.state.players[token].y=best.y
	return true

func travel(w:World,token:String,destination:String)->bool:
	var points:Dictionary=Transit.points(w.player_region(token))
	if points.is_empty():return false
	var cell:Vector2i=points[points.keys()[0]].cell
	return stand(w,token,cell) and seed_act(w,token,"transit",cell,destination) and w.player_region(token)==destination

func arrive(w:World,token:String)->bool:
	story_fixture(w,token)
	place(w,token,"home",Vector2(STALL)+Vector2(0.5,1.5))
	if not seed_act(w,token,"salt_letter",STALL):return false
	if not travel(w,token,Flower.REGION) or not travel(w,token,Salt.REGION):return false
	return stand(w,token,Salt.SALT_WORKER) and seed_act(w,token,"salt_intro",Salt.SALT_WORKER)

func seed_world(path:String)->bool:
	var w:=World.new()
	w.add_player(ALPHA,"alpha")
	w.add_player(BETA,"beta")
	if not arrive(w,ALPHA) or not arrive(w,BETA):return false
	var a:Dictionary=bag_of(w,ALPHA)
	a["plank"]=int(a.get("plank",0))+18
	a["resin"]=int(a.get("resin",0))+3
	a["stone"]=int(a.get("stone",0))+12
	for g in Salt.GATE_ROWS.size():
		var cell:=Vector2i(8,int(Salt.GATE_ROWS[g])+1)
		if not stand(w,ALPHA,cell):return false
		for item in Salt.GATE_MATERIALS:
			if not seed_act(w,ALPHA,"salt_gate_give",cell,item):return false
	if not Salt.repaired(w.state):return false
	var tokens:=[ALPHA,BETA]
	for i in 2:
		var cell:=Salt.pan_rect(Salt.PUBLIC_LOT*2+i).position
		if not stand(w,tokens[i],cell) or not seed_act(w,tokens[i],"salt_flood",cell):return false
	for n in 60:
		if str(w.state.salt_pan.pans[16].s)=="salt" and str(w.state.salt_pan.pans[17].s)=="salt":break
		if not w.step(60.0,true):return false
	for i in 2:
		var cell:=Salt.pan_rect(Salt.PUBLIC_LOT*2+i).position
		if not stand(w,tokens[i],cell) or not seed_act(w,tokens[i],"salt_rake",cell):return false
	if not SB.player_ready(w.state,ALPHA) or not SB.player_ready(w.state,BETA):return false
	# Alpha claims lot 0 and installs her wheel (kit written); the wheel fills both pans.
	var lot0:=Salt.pan_rect(0).position
	if not stand(w,ALPHA,lot0) or not seed_act(w,ALPHA,"salt_claim",lot0):return false
	bag_of(w,ALPHA)["salt_wheel_kit"]=1
	var wheel0:=Salt.wheel_socket(0).position
	if not stand(w,ALPHA,wheel0) or not seed_act(w,ALPHA,"salt_install",wheel0,"wheel"):return false
	var fill:=float(w.state.time)
	if not w.step(290.0,true):return false
	for i in 2:
		var p:Dictionary=w.state.salt_pan.pans[i]
		if str(p.s)!="brine" or float(p.t)!=fill or str(p.f)!="wheel":return false
	if absf(float(SB.pan_progress(w.state,0).p)-290.0)>1e-9 or SB.rainy_now(w.state):return false
	bag_of(w,BETA)["salt_wheel_kit"]=1
	place(w,ALPHA,Salt.REGION,SB.TANK_STAND)
	place(w,BETA,Salt.REGION,SB.TANK_STAND)
	for token in [ALPHA,BETA]:w.state.players[token]["receipts"]={}
	w.active_tokens.clear()
	w.save_path=path
	if not w.save():return false
	seed_time=float(w.state.time)
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.has(SB.STATE_KEY) or float(parsed.time)+200.0>=1440.0:return false
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
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty() and c.session.snapshot.get("salt_pan") is Dictionary

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
		return arrived.call(c.pos()),seconds)
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

## Brine record, lot pans 0..5 (alpha's lot 0, beta's future lot 2) and the bag, as text.
func marks_of(clients:Array)->Array:
	return clients.map(func(x):return [text(x.brine()),text(x.pans().slice(0,6)),text(canon(x.bag()))])

func refuse(c:Client,action:String,p:Vector2i,extra:String,message:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var marks:=marks_of(everyone)
	var r:=await act(c,action,p,extra)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	expect(marks_of(everyone)==marks,"%s: salt_brine, lot pans and bags unchanged in every watching snapshot"%label)

func succeed(c:Client,action:String,p:Vector2i,extra:String,label:String,watchers:Array)->Dictionary:
	var r:=await act(c,action,p,extra)
	expect(r.replied and r.ok,"%s: ok (got ok=%s '%s')"%[label,str(r.ok),str(r.message)])
	await settle([c]+watchers)
	return r

func level_of(c:Client)->int:
	var rec=c.brine()
	if not rec is Dictionary:return -1
	return int(rec.get("level",-1))

func private_check(c:Client,label:String)->void:
	var dump:=JSON.stringify(c.session.snapshot)
	var leaked:=false
	for t:String in [ALPHA,BETA,GAMMA]:
		if dump.contains(t):leaked=true
	expect(not leaked,"%s: %s's snapshot contains no raw token"%[label,c.label])
	var rec=c.brine()
	var keys:Array=rec.keys().map(func(k):return str(k)) if rec is Dictionary else []
	expect(rec==null or (keys==["level"] and not JSON.stringify(rec).contains("token")),"%s: %s's salt_brine is null or exactly {level} (no tokens)"%[label,c.label])

func read_disk()->Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(save_path))

func disk_valid(disk:Variant)->bool:
	return disk is Dictionary and Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func region_of(c:Client)->String:
	return str(c.session.snapshot.get("region_id",""))

static func _keys(d:Dictionary)->Array:
	var out:Array=[]
	for k in d:out.append(str(k))
	out.sort()
	return out

static func _at(d:Dictionary,k:String)->Variant:
	return d[k] if d.has(k) else d.get(StringName(k))

## Field-by-field comparison of a parsed save with a live state (JSON numbers compared by
## value, string/StringName keys alike). Mismatching paths are appended to `out`.
static func close(a:Variant,b:Variant,path:String,out:Array)->void:
	if out.size()>8:return
	var na:bool=a is int or a is float
	var nb:bool=b is int or b is float
	if na and nb:
		if absf(float(a)-float(b))>1e-6*maxf(1.0,absf(float(b))):out.append(path)
		return
	if a is Dictionary and b is Dictionary:
		var ka:=_keys(a)
		if ka!=_keys(b):
			out.append(path+" (keys)")
			return
		for k:String in ka:close(_at(a,k),_at(b,k),path+"."+k,out)
		return
	if a is Array and b is Array:
		if a.size()!=b.size():
			out.append(path+" (size)")
			return
		for i in a.size():close(a[i],b[i],"%s[%d]"%[path,i],out)
		return
	if (a is String or a is StringName) and (b is String or b is StringName):
		if str(a)!=str(b):out.append(path)
		return
	if typeof(a)!=typeof(b) or a!=b:out.append(path)

## Every cell the walk can touch must be standable (polyline sampled every 0.25 tiles,
## plus a 0.5-tile overshoot band).
func path_standable(w:World)->bool:
	w.switch_region(Salt.REGION)
	var ok:=true
	var tank_x:=SB.TANK_STAND.x
	var y:=SB.TANK_STAND.y
	while y<=float(ROW_Y)+1.0:
		for dx in [0.0,0.5]:
			if not w.can_stand(Vector2(tank_x+dx,y)):ok=false
		y+=0.25
	var x:=float(LOT_X)+0.25
	while x<=tank_x+0.5:
		for dy in [0.5,1.0]:
			if not w.can_stand(Vector2(x,float(ROW_Y)+dy)):ok=false
		x+=0.25
	y=float(ROW_Y)+1.0
	while y>=16.5:
		for lx in [float(LOT_X)+0.5,float(LOT_X)+0.9]:
			if not w.can_stand(Vector2(lx,y)):ok=false
		y-=0.25
	w.switch_region("home")
	return ok

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("salt-brine-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"SEEDED FIXTURE (letters, trips, gates, hand rakes, alpha's claim/wheel/fill earned offline; kits/spots written; no salt_brine) accepted by SaveSchema"):return false
	expect(Salt.pan_at(CLAIM_CELL)==BETA_LOT*2 and Salt.wheel_socket(BETA_LOT).has_point(WHEEL_CELL),"premise: claim/wheel cells belong to lot 2")
	var probe:=World.new()
	if not expect(probe.load_world(save_path),"probe: seeded save loads"):return false
	expect(path_standable(probe),"probe: 北門 walk tank → south → west along row 18 → north to lot 2 (and back) is standable")
	probe=null
	var port:=start_server()
	if not expect(port>0,"server Session hosts on 127.0.0.1 (websocket)"):return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	if not expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback"):return false
	expect(server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer,"server and clients use WebSocketMultiplayerPeer")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World")
	await settle([alpha,beta])
	expect(region_of(alpha)=="beimen" and region_of(beta)=="beimen","alpha and beta are in 北門")
	print("SALT_BRINE_SESSION_LABEL machine=single process=single transport=websocket loopback=127.0.0.1:%d clients=2(+late joiner) fixture=SEEDED(letters,trips,gates,hand rakes,alpha lot+wheel+fill earned offline; kits,spots written) shutdown=normal-only"%port)

	# 1. Fresh: no record; alpha can store 6 from each pan, beta has no unit.
	var a_snap:Dictionary=alpha.session.snapshot
	var b_snap:Dictionary=beta.session.snapshot
	expect(alpha.brine()==null and beta.brine()==null and SB.level(a_snap)==0,"case 1: no salt_brine key yet")
	var rows:=SB.rows(a_snap)
	expect(rows.size()==2 and int(rows[0].store)==6 and int(rows[1].store)==6 and rows[0].pour_block==SB.TANK_EMPTY,"case 1: alpha's client rows: store 6 / 6, pour blocked (TANK_EMPTY) (%s)"%JSON.stringify(rows))
	expect(SB.common_block(b_snap)==SB.NO_UNIT and SB.rows(b_snap).is_empty(),"case 1: beta's client sees NO_UNIT")
	for c:Client in [alpha,beta]:private_check(c,"case 1")

	# 2. Refusals leave both ends unchanged.
	await refuse(beta,SB.STORE_ACTION,SB.TANK,"a",SB.NO_UNIT,"case 2 beta (no unit) stores",[alpha])
	await refuse(beta,SB.POUR_ACTION,SB.TANK,"a",SB.NO_UNIT,"case 2 beta (no unit) pours",[alpha])
	await refuse(alpha,SB.POUR_ACTION,SB.TANK,"a",SB.TANK_EMPTY,"case 2 alpha pours from an empty tank",[beta])
	await refuse(alpha,SB.STORE_ACTION,SB.TANK,"c",SB.BAD_PAN,"case 2 alpha names no pan",[beta])
	await refuse(alpha,SB.STORE_ACTION,Salt.SALT_WORKER,"a",SB.WRONG_CELL,"case 2 alpha stores at 阿曬",[beta])

	# 3. Alpha stores her west pan; both clients see the level and the reduced pan.
	var first:=await succeed(alpha,SB.STORE_ACTION,SB.TANK,"a","case 3 alpha stores pan 0",[beta])
	expect(str(first.message)==SB.STORE_OK%[6,6],"case 3 message '%s'"%str(first.message))
	await wait_until(func():return level_of(beta)==6,3.0)
	for c:Client in [alpha,beta]:
		var p0:=c.pan(0)
		expect(level_of(c)==6,"case 3 %s sees level 6"%c.label)
		expect(str(p0.get("s",""))=="brine" and float(p0.get("p",-1.0))>=0.0 and float(p0.get("p",99.0))<48.0 and float(p0.get("t",0.0))>=seed_time and str(p0.get("f",""))=="wheel","case 3 %s sees pan 0 reduced below one bucket (%s)"%[c.label,str(p0)])
	expect(text(alpha.pan(0))==text(beta.pan(0)) and float(alpha.pan(1).get("p",-1.0))==0.0,"case 3 both see the same pan 0; pan 1 untouched")
	expect(int(SB.pan_progress(alpha.session.snapshot,0).tenths)==0 and int(SB.rows(alpha.session.snapshot)[0].store)==0,"case 3 alpha's client: pan 0 at 0 tenths, nothing more to store")

	# 4. Replay of a used sequence (with the other side) is dropped.
	await settle([alpha,beta])
	var counts:=[alpha.notices.size(),beta.notices.size()]
	var before4:=marks_of([alpha,beta])
	alpha.session.request_action.rpc_id(1,int(first.sequence),SB.STORE_ACTION,SB.TANK,"b",region_of(alpha),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==counts[0] and beta.notices.size()==counts[1],"case 4 re-sent sequence %d gets no notice"%int(first.sequence))
	expect(marks_of([alpha,beta])==before4,"case 4 re-sent sequence changes nothing on either end")

	# 5. Alpha stores her east pan too.
	var second:=await succeed(alpha,SB.STORE_ACTION,SB.TANK,"b","case 5 alpha stores pan 1",[beta])
	expect(str(second.message)==SB.STORE_OK%[6,12],"case 5 message '%s'"%str(second.message))
	await wait_until(func():return level_of(beta)==12,3.0)
	expect(level_of(alpha)==12 and level_of(beta)==12 and float(beta.pan(1).get("p",99.0))<48.0,"case 5 both see level 12 and pan 1 reduced")

	# 6. Beta walks to lot 2, claims it, installs her wheel, walks back and pours.
	expect(await walk(beta,Vector2.DOWN,func(at:Vector2):return at.y>=float(ROW_Y)+0.3,8.0),"case 6 beta walks south from the tank (y=%.2f)"%beta.pos().y)
	expect(await walk(beta,Vector2.LEFT,func(at:Vector2):return at.x<=float(LOT_X)+1.0,10.0),"case 6 beta walks west along row %d (x=%.2f)"%[ROW_Y,beta.pos().x])
	expect(await walk(beta,Vector2.UP,func(at:Vector2):return at.y<=16.9,6.0),"case 6 beta walks north to lot 2 (y=%.2f)"%beta.pos().y)
	var at_lot:=beta.pos()
	expect(at_lot.distance_to(Vector2(CLAIM_CELL)+Vector2(0.5,0.5))<=3.1 and at_lot.distance_to(Vector2(WHEEL_CELL)+Vector2(0.5,0.5))<=3.1,"case 6 beta stands within reach of lot 2's pan and wheel socket (%s)"%str(at_lot))
	await refuse(beta,SB.STORE_ACTION,SB.TANK,"a",SB.TOO_FAR,"case 6 beta at lot 2 is too far from the tank",[alpha])
	await succeed(beta,"salt_claim",CLAIM_CELL,"","case 6 beta claims lot 2",[alpha])
	await succeed(beta,"salt_install",WHEEL_CELL,"wheel","case 6 beta installs her wheel",[alpha])
	expect(await wait_until(func():return str(beta.pan(4).get("s",""))=="brine" and str(beta.pan(5).get("s",""))=="brine",3.0),"case 6 the wheel fills beta's pans 4 and 5")
	var unit:Dictionary=SB.unit(beta.session.snapshot)
	expect(int(unit.index)==BETA_LOT and unit.kind=="lot" and unit.wheel==true and SB.pan_ids(beta.session.snapshot)==[4,5],"case 6 beta's client: own unit lot 2 with a wheel, pans 4/5 (%s)"%str(unit))
	expect(int(bag_view(beta).get("salt_wheel_kit",0))==0,"case 6 the kit left beta's bag")
	expect(await walk(beta,Vector2.DOWN,func(at:Vector2):return at.y>=float(ROW_Y)+0.3,6.0),"case 6 beta walks back south (y=%.2f)"%beta.pos().y)
	expect(await walk(beta,Vector2.RIGHT,func(at:Vector2):return at.x>=SB.TANK_STAND.x-0.2,10.0),"case 6 beta walks east along row %d (x=%.2f)"%[ROW_Y,beta.pos().x])
	expect(await walk(beta,Vector2.UP,func(at:Vector2):return at.y<=16.4,6.0),"case 6 beta walks north to the tank (y=%.2f)"%beta.pos().y)
	expect(beta.pos().distance_to(Vector2(SB.TANK)+Vector2(0.5,0.5))<=SB.REACH,"case 6 beta is back within reach of the tank (%s)"%str(beta.pos()))
	var b_rows:=SB.rows(beta.session.snapshot)
	expect(b_rows.size()==2 and int(b_rows[0].pour)==9 and b_rows[0].pour_block=="","case 6 beta's client: pour 9 into pan 4 (%s)"%JSON.stringify(b_rows))
	var poured:=await succeed(beta,SB.POUR_ACTION,SB.TANK,"a","case 6 beta pours alpha's brine into her pan 4",[alpha])
	expect(str(poured.message)==SB.POUR_OK%[9,9,3],"case 6 pour message '%s'"%str(poured.message))
	await wait_until(func():return level_of(alpha)==3,3.0)
	for c:Client in [alpha,beta]:
		var p4:=c.pan(4)
		expect(level_of(c)==3 and float(p4.get("p",-1.0))>=432.0 and float(p4.get("p",999.0))<=Salt.NEED-1.0 and str(p4.get("s",""))=="brine","case 6 %s sees level 3 and pan 4 at 432..479 (%s)"%[c.label,str(p4)])
	await refuse(beta,SB.POUR_ACTION,SB.TANK,"a",SB.PAN_RICH,"case 6 pan 4 cannot take another bucket",[alpha])
	await refuse(alpha,SB.POUR_ACTION,SB.TANK,"",SB.BAD_PAN,"case 6 alpha pours into no pan",[beta])
	for c:Client in [alpha,beta]:private_check(c,"case 6")

	# 7. Reconnect keeps the shared level.
	await leave(beta)
	beta=null
	await pause(0.3)
	beta=await join("beta",BETA,port)
	if not expect(joined(beta),"case 7 beta reconnects"):return false
	await settle([alpha,beta])
	expect(level_of(beta)==3 and SB.common_block(beta.session.snapshot)=="","case 7 reconnected beta sees level 3 and her wheel lot")

	# 8. Normal shutdown → the save equals the server state field by field.
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	await pause(0.4)
	var live:Dictionary=server.world.state.duplicate(true) # read-only; clock paused with no peers
	expect(await stop_server(),"case 8 server shuts down with a final save")
	var disk=read_disk()
	if not expect(disk is Dictionary,"case 8 save parses"):return false
	expect(disk_valid(disk),"case 8 saved world passes SaveSchema")
	var diff:=[]
	close(disk,live,"state",diff)
	expect(diff.is_empty(),"case 8 on-disk save equals the server state field by field (mismatch: %s)"%str(diff))
	var rec=disk.get(SB.STATE_KEY,{})
	expect(rec is Dictionary and rec.size()==1 and float(rec.get("level",-1))==3.0,"case 8 save: salt_brine is exactly {level:3}")
	expect(str(disk.salt_pan.lots[0].owner)==ALPHA and str(disk.salt_pan.lots[BETA_LOT].owner)==BETA and disk.salt_pan.lots[BETA_LOT].wheel==true,"case 8 save: alpha holds lot 0, beta lot 2 with a wheel")
	expect(float(disk.salt_pan.pans[0].p)<48.0 and float(disk.salt_pan.pans[1].p)<48.0 and float(disk.salt_pan.pans[4].p)>=432.0,"case 8 save: pans 0/1 hold the remainders, pan 4 the poured brine")
	expect(SB.level(disk)==3 and SB.valid(disk.duplicate(true)),"case 8 save: SaltBrine.level / valid read the saved record")

	# 9. Restart; everyone, including a late joiner, sees the same level.
	var port2:=start_server()
	if not expect(port2>0,"case 9 restarted server hosts the same save"):return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	if not expect(joined(alpha) and joined(beta),"case 9 both rejoin"):return false
	await settle([alpha,beta])
	for c:Client in [alpha,beta]:expect(level_of(c)==3,"case 9 %s: restart keeps level 3"%c.label)
	gamma=await join("gamma",GAMMA,port2)
	if not expect(joined(gamma),"case 9 late joiner gamma joins"):return false
	await settle([alpha,beta,gamma])
	expect(level_of(gamma)==3 and SB.level(gamma.session.snapshot)==3,"case 9 gamma sees level 3")
	expect(SB.common_block(gamma.session.snapshot)==SB.NOT_READY and SB.rows(gamma.session.snapshot).is_empty(),"case 9 gamma's client: rake by hand in 北門 first (NOT_READY)")
	private_check(gamma,"case 9")
	await refuse(gamma,SB.STORE_ACTION,SB.TANK,"a",SB.WRONG_REGION,"case 9 gamma (at home) cannot use the tank",[alpha,beta])
	await leave(gamma)
	gamma=null
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 9 restarted server shuts down cleanly")
	var after=read_disk()
	expect(disk_valid(after) and text(after.get(SB.STATE_KEY))==text(disk.get(SB.STATE_KEY)) and after.players.has(GAMMA),"case 9 final save valid, salt_brine unchanged, gamma recorded")
	return true

func bag_view(c:Client)->Dictionary:
	return c.bag()

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
