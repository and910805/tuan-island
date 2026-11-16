extends SceneTree
## T066 居民好感 (resident bond) two-client Session acceptance: per-player and
## private progress for aru (village NPC at home) and mianmian (ranch resident at
## home, picnic-gated), over a real dedicated server and real WebSocket clients.
##
## LEVEL: one machine, ONE Godot process. Inside the single SceneTree a real
## dedicated server Session listens on a free 127.0.0.1 port with the WebSocket
## transport (WebSocketMultiplayerPeer); separate client Session nodes join it
## over loopback, each in its own branch with its own SceneMultiplayer, so every
## request, notice and snapshot travels the RPC + WebSocket path. Clients only
## read their own received snapshots; the server World is never touched after
## seeding, except for reading the on-disk save after each normal shutdown.
##
## SEEDED FIXTURE (disclosed; written to a fresh TEMP folder and validated with
## SaveSchema before the server starts): picnic=true; state.time=3*1440-240
## (world day 2, 240 world seconds before the day-3 boundary); alpha stands just
## beside aru's cell, beta just beside mianmian's ranch cell (cells taken from
## World.bond_place on a probe save loaded like the server's, which also gives
## the BFS walking routes); exact bags alpha {tea_light 1,
## radish 2, wood 5}, beta {feed 3, wool 1, radish 2, wood 5}. Second short run
## (case 10): separate save with picnic=false (and dock_stage never set), islander
## "delta" standing within reach of both the ranch cell and achao's first dock
## cell, holding {feed 1, radish 1}; both mianmian and achao refuse over the network.
## Fifth batch (luoluo 洛洛 / lingpopo 鈴婆婆, case 11 and case 10b): beta's preset
## bag additionally holds {soup 2} (a lingpopo liked gift). Their cells are NEVER
## hard-coded: they come from World.bond_place on the probe saves at run time
## (POST_CELLS / BELL_CELLS may change). In case 11 alpha WALKS over the network
## from the ranch to luoluo and beta WALKS from the ranch to lingpopo (routes
## planned on the probe world); in case 10b two extra islanders "epsilon" {bread 1}
## and "zeta" {soup 1} are PRESET (position + bag) beside luoluo's / lingpopo's
## cells of the picnic-less probe world and are refused with POST_LOCKED /
## BELL_LOCKED over the network.
## Sixth batch (diandian 點點, case 10c, same picnic-less run): islander "eta"
## {star_mushroom 1, radish 1} is PRESET in region star_garden standing just below
## Bond.GARDEN_CELL, and "theta" {} is PRESET in star_garden at 30.5,29.5 (well
## out of reach). diandian has no gate, so eta's talk and liked gift succeed over
## the network while theta is refused (out of reach / wrong cell).
## Everything after the seed goes through client Sessions over the network:
## talks, gifts, every refusal, the walks between aru, the ranch, luoluo and
## lingpopo (movement RPCs steered from the client's own snapshot),
## disconnect/rejoin, the sequence replays, shutdowns and restarts. No bonds are
## ever preset.
## Clock: world time only advances on the live server. The day boundary is
## produced by the preset state.time (240 s before midnight, set BEFORE the
## server starts) plus a temporary Engine.time_scale (TIME_SCALE) inside this
## one process after cases 1-7; real-time waits/timers ignore the time scale.
## A guard check asserts the run is still on day 2 just before the fast-forward.
## Replay (case 6): the only resend reachable from the Session API is the raw
## `request_action` RPC with the already-used sequence number (the pattern used
## by test_glass_furnace_session); Session drops it before World sees it. World
## request-id receipts (same request id) are covered at rule level by
## test_resident_bond.gd, not here.
## "Same tick" (case 5): both clients issue their talk in the same client frame;
## the test cannot force the server to process both in one physics tick, it
## only proves there is no contention between the two requests.
## NOT covered: multiple processes, cross-machine, TLS/wss, latency/packet loss
## injection, crash durability (only normal shutdowns with a final save).
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const Regions=preload("res://scripts/regions.gd")
const KEY:="resident-bond-session"
const ALPHA:="bond-session-alpha-token"
const BETA:="bond-session-beta-token"
const GAMMA:="bond-session-gamma-token"
const DELTA:="bond-session-delta-token"
const EPSILON:="bond-session-epsilon-token"
const ZETA:="bond-session-zeta-token"
const ETA:="bond-session-eta-token"
const THETA:="bond-session-theta-token"
const RESIDENT_COUNT:=12
const GARDEN_REGION:="star_garden"
const ETA_BAG:={"star_mushroom":1,"radish":1}
const THETA_BAG:={"radish":1}
const THETA_AT:=Vector2(30.5,29.5)
const DAY:=1440.0
const START_DAY:=2
const START_TIME:=3.0*DAY-240.0
const TIME_SCALE:=30.0
const HALF:=Vector2(0.5,0.5)
const ALPHA_BAG:={"tea_light":1,"radish":2,"wood":5}
const BETA_BAG:={"feed":3,"wool":1,"radish":2,"wood":5,"soup":2}
const DELTA_BAG:={"feed":1,"radish":1}
const EPSILON_BAG:={"bread":1}
const ZETA_BAG:={"soup":1}
## World.gd literals: bond place gate and the generic 3.2-tile reach gate.
const MSG_PLACE:="請走到這位居民身邊。"
const MSG_FAR:="靠近一點，才能和它互動"

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
	func region()->String:
		return str(session.snapshot.get("region_id",""))
	func pos()->Vector2:
		var p:=me()
		return Vector2(float(p.get("x",-99.0)),float(p.get("y",-99.0)))
	func bag()->Dictionary:
		var inv=me().get("inventory",{})
		return inv if inv is Dictionary else {}
	func clock()->float:
		return float(session.snapshot.get("time",-1.0))
	func bonds()->Dictionary:
		var v=session.snapshot.get("resident_bonds",null)
		return v if v is Dictionary else {}

var checks:=0
var failures:=0
var serial:=0
var folder:=""
var save_path:=""
var server
var server_branch:Node
var finished:=false
var aru_cell:=Vector2i.ZERO
var ranch_cell:=Vector2i.ZERO
var aru_stand:=Vector2.ZERO
var ranch_a:=Vector2.ZERO
var ranch_b:=Vector2.ZERO
var to_ranch:Array=[]
var to_aru:Array=[]
var dock_cell:=Vector2i.ZERO
## Case 10 stand: within reach of both mianmian's ranch cell and achao's dock cell.
var lock_stand:=Vector2.ZERO
## Fifth batch, picnic world (all derived from World.bond_place on the probe).
var post_cell:=Vector2i.ZERO
var bell_cell:=Vector2i.ZERO
var post_a:=Vector2.ZERO
var bell_b:=Vector2.ZERO
var post_wrong:=Vector2i.ZERO
var bell_wrong:=Vector2i.ZERO
var to_post:Array=[]
var to_bell:Array=[]
var post_to_aru:Array=[]
## Fifth batch, picnic-less world (case 10b), from its own probe.
var lock_post_cell:=Vector2i.ZERO
var lock_bell_cell:=Vector2i.ZERO
var lock_post_stand:=Vector2.ZERO
var lock_bell_stand:=Vector2.ZERO

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)
	return ok

func _initialize()->void:
	create_timer(150.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	Engine.time_scale=1.0
	print("RESIDENT_BOND_SESSION watchdog fired before completion")
	print("RESIDENT_BOND_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	Engine.time_scale=1.0
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("RESIDENT_BOND_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("RESIDENT_BOND_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("RESIDENT_BOND_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

static func stand_near(w,cell:Vector2i,skip:Vector2=Vector2.INF)->Vector2:
	for off:Vector2 in [Vector2(0.5,1.5),Vector2(1.5,1.5),Vector2(-0.5,1.5),Vector2(1.5,0.5),Vector2(-0.5,0.5),Vector2(0.5,-0.5)]:
		var at:Vector2=Vector2(cell)+off
		if at!=skip and w.can_stand(at):return at
	return Vector2.ZERO

## 4-neighbour BFS over standable cell centres; returns corner waypoints plus `to`.
static func route(w,from:Vector2,to:Vector2)->Array:
	var start:=Vector2i(floori(from.x),floori(from.y))
	var goal:=Vector2i(floori(to.x),floori(to.y))
	var prev:={start:start}
	var queue:Array=[start]
	var head:=0
	while head<queue.size() and not prev.has(goal):
		var cur:Vector2i=queue[head]
		head+=1
		for step:Vector2i in [Vector2i.RIGHT,Vector2i.LEFT,Vector2i.DOWN,Vector2i.UP]:
			var nxt:Vector2i=cur+step
			if prev.has(nxt) or nxt.x<1 or nxt.y<1 or nxt.x>=World.SIZE.x-1 or nxt.y>=World.SIZE.y-1:continue
			if not w.can_stand(Vector2(nxt)+HALF):continue
			prev[nxt]=cur
			queue.append(nxt)
	if not prev.has(goal):return []
	var cells:Array=[goal]
	while cells.back()!=start:cells.append(prev[cells.back()])
	cells.reverse()
	var points:Array=[]
	for i in range(1,cells.size()-1):
		var a:Vector2i=cells[i]-cells[i-1]
		var b:Vector2i=cells[i+1]-cells[i]
		if a!=b:points.append(Vector2(cells[i])+HALF)
	points.append(to)
	return points

## Stands and walking routes are computed on a probe world that went through the
## same save -> load path the server uses (loading picnic saves places the
## community table, which blocks a home cell).
func plan()->bool:
	var probe:=folder.path_join("probe.json")
	if not expect(seed_world(probe,true,{}),"probe fixture saved"):return false
	var w:=World.new()
	if not expect(w.load_world(probe),"probe fixture loads like the server's save"):return false
	var aru_place:Array=World.bond_place(w.state,"aru")
	var ranch_place:Array=World.bond_place(w.state,"mianmian")
	aru_cell=aru_place[1]
	ranch_cell=ranch_place[1]
	expect(str(aru_place[0])==Regions.HOME and str(ranch_place[0])==Regions.HOME,"aru and mianmian both live in the home region")
	expect(ranch_cell==Vector2i(49,33),"mianmian's ranch cell on the fixture is the default (49,33) (got %s)"%str(ranch_cell))
	aru_stand=stand_near(w,aru_cell)
	ranch_b=stand_near(w,ranch_cell)
	ranch_a=stand_near(w,ranch_cell,ranch_b)
	for spot:Array in [["aru",aru_stand,aru_cell],["ranch beta",ranch_b,ranch_cell],["ranch alpha",ranch_a,ranch_cell]]:
		var at:Vector2=spot[1]
		var cell:Vector2i=spot[2]
		if not expect(at!=Vector2.ZERO and at.distance_to(Vector2(cell)+HALF)<=3.2,"%s stand %s is standable and within 3.2 of %s"%[spot[0],str(at),str(cell)]):return false
	expect(aru_stand.distance_to(Vector2(ranch_cell)+HALF)>3.2,"aru's stand is out of reach of mianmian (%.2f tiles)"%aru_stand.distance_to(Vector2(ranch_cell)+HALF))
	var dock_place:Array=World.bond_place(w.state,"achao")
	dock_cell=dock_place[1]
	expect(str(dock_place[0])==Regions.HOME and dock_cell==Bond.DOCK_CELLS[0],"achao's dock cell on the fixture is home %s (got %s %s)"%[str(Bond.DOCK_CELLS[0]),str(dock_place[0]),str(dock_cell)])
	for cell:Vector2i in [Vector2i(49,32),Vector2i(50,32),Vector2i(48,32),Vector2i(51,32)]:
		var at:=Vector2(cell)+HALF
		if w.can_stand(at) and at.distance_to(Vector2(ranch_cell)+HALF)<=3.2 and at.distance_to(Vector2(dock_cell)+HALF)<=3.2:
			lock_stand=at
			break
	if not expect(lock_stand!=Vector2.ZERO,"a standable spot within 3.2 of both the ranch cell and the dock cell (%s)"%str(lock_stand)):return false
	to_ranch=route(w,aru_stand,ranch_a)
	to_aru=route(w,ranch_a,aru_stand)
	if not expect(not to_ranch.is_empty() and not to_aru.is_empty(),"walkable home route between aru and the ranch (%d / %d waypoints)"%[to_ranch.size(),to_aru.size()]):return false
	# Fifth batch: luoluo / lingpopo cells as the server will compute them.
	var post_place:Array=World.bond_place(w.state,"luoluo")
	var bell_place:Array=World.bond_place(w.state,"lingpopo")
	post_cell=post_place[1]
	bell_cell=bell_place[1]
	expect(str(post_place[0])==Regions.HOME and str(bell_place[0])==Regions.HOME,"luoluo and lingpopo both live in the home region")
	expect(post_cell in Bond.POST_CELLS and post_cell==Bond.post_cell(w.state),"luoluo's cell %s is one of POST_CELLS %s"%[str(post_cell),str(Bond.POST_CELLS)])
	expect(bell_cell in Bond.BELL_CELLS and bell_cell==Bond.bell_cell(w.state),"lingpopo's cell %s is one of BELL_CELLS %s"%[str(bell_cell),str(Bond.BELL_CELLS)])
	post_a=stand_near(w,post_cell)
	bell_b=stand_near(w,bell_cell)
	for spot:Array in [["luoluo alpha",post_a,post_cell],["lingpopo beta",bell_b,bell_cell]]:
		var at:Vector2=spot[1]
		var cell:Vector2i=spot[2]
		if not expect(at!=Vector2.ZERO and at.distance_to(Vector2(cell)+HALF)<=3.2,"%s stand %s is standable and within 3.2 of %s"%[spot[0],str(at),str(cell)]):return false
	if not expect(post_a.distance_to(Vector2(bell_cell)+HALF)>3.2,"luoluo's stand is out of reach of lingpopo (%.2f tiles)"%post_a.distance_to(Vector2(bell_cell)+HALF)):return false
	post_wrong=wrong_cell(post_cell,post_a)
	bell_wrong=wrong_cell(bell_cell,bell_b)
	if not expect(post_wrong!=post_cell and bell_wrong!=bell_cell,"a reachable neighbour cell beside luoluo (%s) and lingpopo (%s)"%[str(post_wrong),str(bell_wrong)]):return false
	to_post=route(w,ranch_a,post_a)
	to_bell=route(w,ranch_b,bell_b)
	post_to_aru=route(w,post_a,aru_stand)
	if not expect(not to_post.is_empty() and not to_bell.is_empty() and not post_to_aru.is_empty(),"walkable home routes ranch->luoluo, ranch->lingpopo, luoluo->aru (%d / %d / %d waypoints)"%[to_post.size(),to_bell.size(),post_to_aru.size()]):return false
	# Picnic-less probe for case 10b: same save -> load path, its own cells.
	var probe_locked:=folder.path_join("probe-locked.json")
	if not expect(seed_world(probe_locked,false,{}),"picnic-less probe fixture saved"):return false
	var lw:=World.new()
	if not expect(lw.load_world(probe_locked),"picnic-less probe loads like the server's save"):return false
	lock_post_cell=World.bond_place(lw.state,"luoluo")[1]
	lock_bell_cell=World.bond_place(lw.state,"lingpopo")[1]
	lock_post_stand=stand_near(lw,lock_post_cell)
	lock_bell_stand=stand_near(lw,lock_bell_cell)
	return expect(lock_post_stand!=Vector2.ZERO and lock_bell_stand!=Vector2.ZERO,"picnic-less stands beside luoluo %s (%s) and lingpopo %s (%s)"%[str(lock_post_cell),str(lock_post_stand),str(lock_bell_cell),str(lock_bell_stand)])

## A 4-neighbour of `cell` that is still within the 3.2 reach of `stand`, so the
## server answers with the place check rather than the reach check.
static func wrong_cell(cell:Vector2i,stand:Vector2)->Vector2i:
	for step:Vector2i in [Vector2i.RIGHT,Vector2i.LEFT,Vector2i.DOWN,Vector2i.UP]:
		var c:=cell+step
		if stand.distance_to(Vector2(c)+HALF)<=3.2:return c
	return cell

func seed_world(path:String,picnic:bool,people:Dictionary)->bool:
	var w:=World.new()
	w.save_path=path
	w.state["picnic"]=picnic
	w.state["time"]=START_TIME
	for token:String in people:
		var spec:Dictionary=people[token]
		w.add_player(token,str(spec.name))
		var p:Dictionary=w.state.players[token]
		var at:Vector2=spec.at
		p["x"]=at.x
		p["y"]=at.y
		p["inventory"]=(spec.inv as Dictionary).duplicate()
		if spec.has("region"):p["region"]=str(spec.region)
	w.active_tokens.clear()
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:return false
	for token:String in people:
		if parsed.players.get(token,{}).has("bonds"):return false
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
	await wait_until(func():return not c.session.own_id.is_empty() and not c.me().is_empty() and not c.bonds().is_empty(),8.0)
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

## Steers the client through `points` with movement RPCs, reading only its own
## received snapshot position; stops with a zero direction at the end.
func walk(c:Client,points:Array,seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000.0)
	for i in points.size():
		var target:Vector2=points[i]
		var tolerance:=0.12 if i==points.size()-1 else 0.3
		while true:
			if Time.get_ticks_msec()>deadline:
				c.session.input_direction(Vector2.ZERO)
				return false
			var d:Vector2=target-c.pos()
			if d.length()<=tolerance:break
			c.session.input_direction(d.normalized()*clampf(d.length()/0.8,0.2,1.0))
			await process_frame
	c.session.input_direction(Vector2.ZERO)
	await pause(0.3)
	await settle([c])
	return true

func fast_forward(condition:Callable,seconds:float)->bool:
	Engine.time_scale=TIME_SCALE
	var ok:=await wait_until(condition,seconds)
	Engine.time_scale=1.0
	await pause(0.2)
	return ok

# ---------------------------------------------------------------- helpers --

static func canon(d:Variant)->Dictionary:
	var out:={}
	if not d is Dictionary:return {"<invalid>":-1}
	for item in d:
		if int(d[item])!=0:out[str(item)]=int(d[item])
	return out

static func plus(a:Dictionary,b:Dictionary,sign:int=1)->Dictionary:
	var out:=canon(a)
	for item in b:
		out[str(item)]=int(out.get(str(item),0))+sign*int(b[item])
		if int(out[str(item)])==0:out.erase(str(item))
	return out

static func text(d:Variant)->String:
	return JSON.stringify(d,"",true)

## Whole received view, normalised to [points, stage, stage_name, next, talked_today, gifted_today].
static func rows(v:Dictionary)->Dictionary:
	var out:={}
	for resident in v:
		var e=v[resident]
		if not e is Dictionary:
			out[str(resident)]="<invalid>"
			continue
		out[str(resident)]=[int(e.get("points",-1)),int(e.get("stage",-1)),str(e.get("stage_name","")),int(e.get("next",-1)),
			e.get("talked_today") if e.get("talked_today") is bool else "?",e.get("gifted_today") if e.get("gifted_today") is bool else "?"]
	return out

## Expected whole view: spec maps resident -> [points, talked_today, gifted_today]; all others fresh.
static func expected_rows(spec:Dictionary)->Dictionary:
	var out:={}
	for resident:String in Bond.RESIDENTS:
		var s:Array=spec.get(resident,[0,false,false])
		var pts:int=int(s[0])
		var stage:int=Bond.stage_for(pts)
		out[resident]=[pts,stage,Bond.stage_name(stage),int(Bond.THRESHOLDS[stage]) if stage<Bond.THRESHOLDS.size() else Bond.LIMIT,bool(s[1]),bool(s[2])]
	return out

func expect_view(c:Client,spec:Dictionary,label:String)->bool:
	var got:=text(rows(c.bonds()))
	var want:=text(expected_rows(spec))
	return expect(got==want,"%s: %s's whole resident_bonds view is exactly %s (got %s)"%[label,c.label,text(spec),got])

static func rec(points:int,talk:int,gift:int)->Dictionary:
	return {"points":points,"talk_day":talk,"gift_day":gift}

static func disk_bonds(person:Variant)->Variant:
	if not person is Dictionary or not person.has("bonds"):return null
	var b=person.bonds
	if not b is Dictionary:return "<invalid>"
	var out:={}
	for resident in b:
		var r=b[resident]
		out[str(resident)]=rec(int(r.get("points",-99)),int(r.get("talk_day",-99)),int(r.get("gift_day",-99))) if r is Dictionary and r.size()==3 else "<invalid>"
	return out

## before/after are STAGES (0-4), not points.
static func talk_msg(resident:String,day:int,before:int,after:int)->String:
	var lines:Array=Bond.TALK_LINES[resident]
	var message:="%s：%s"%[Bond.name_of(resident),lines[posmod(day,lines.size())]]
	var raised:=Bond.stage_up_text(resident,before,after)
	return message if raised.is_empty() else message+" "+raised

static func liked_msg(resident:String,item:String,before:int,after:int)->String:
	var message:="%s很喜歡%s，小心地收了起來。"%[Bond.name_of(resident),World.NAMES[item]]
	var raised:=Bond.stage_up_text(resident,before,after)
	return message if raised.is_empty() else message+" "+raised

static func repeat_gift_msg(resident:String,item:String)->String:
	return "%s收下了%s。今天的心意已經記過，好感明天再算。"%[Bond.name_of(resident),World.NAMES[item]]

static func talked_msg(resident:String)->String:
	return "今天已經和%s聊過了，明天再來坐坐。"%Bond.name_of(resident)

static func keep_msg(resident:String)->String:
	return "%s說這個你先留著用。"%Bond.name_of(resident)

static func missing_msg(item:String)->String:
	return "背包裡沒有%s。"%World.NAMES[item]

## Exact refusal; whole bag and whole bonds view unchanged for the actor and every watcher.
func refuse(c:Client,action:String,p:Vector2i,extra:String,message:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var bags:Array=everyone.map(func(x):return canon(x.bag()))
	var views:Array=everyone.map(func(x):return text(rows(x.bonds())))
	var r:=await act(c,action,p,extra)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	var same:=true
	for i in everyone.size():
		if canon(everyone[i].bag())!=bags[i] or text(rows(everyone[i].bonds()))!=views[i]:same=false
	expect(same,"%s: every bag and every resident_bonds view unchanged in all watching snapshots"%label)

## Privacy of `c`'s received snapshot with respect to `others`.
func private_check(c:Client,others:Array,label:String)->void:
	var people=c.session.snapshot.get("players",{})
	for o:Client in others:
		var them=people.get(o.session.own_id,null) if people is Dictionary else null
		expect(them is Dictionary and not them.has("bonds") and not them.has("resident_bonds"),"%s: %s's snapshot entry for %s exists and has no bonds / resident_bonds (ids %s)"%[label,c.label,o.label,str(people.keys()) if people is Dictionary else "?"])
	expect(not c.me().has("bonds"),"%s: %s's own player entry carries no raw bonds record"%[label,c.label])
	var dump:=JSON.stringify(c.session.snapshot)
	expect(not dump.contains("talk_day") and not dump.contains("gift_day"),"%s: %s's whole snapshot contains no raw bond record field"%[label,c.label])
	expect(dump.count("\"resident_bonds\"")==1,"%s: %s's snapshot carries exactly one resident_bonds (its own)"%[label,c.label])
	var leaked:=false
	for o:Client in others+[c]:
		if dump.contains(o.token):leaked=true
	expect(not leaked,"%s: %s's snapshot contains no private token"%[label,c.label])

# --------------------------------------------------------------- scenario --

var alpha:Client
var beta:Client
var gamma:Client
var delta:Client
var epsilon:Client
var zeta:Client
var eta:Client
var theta:Client

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("resident-bond-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	if not plan():return false
	save_path=folder.path_join("world.json")
	var seeded:=seed_world(save_path,true,{ALPHA:{"name":"alpha","at":aru_stand,"inv":ALPHA_BAG},BETA:{"name":"beta","at":ranch_b,"inv":BETA_BAG}})
	if not expect(seeded,"SEEDED FIXTURE (picnic, time, positions, bags; no bonds) written to TEMP and accepted by SaveSchema.validate"):return false
	var port:=start_server()
	expect(port>0,"server Session hosts on 127.0.0.1 with the websocket transport")
	if port==0:return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback and received their own snapshot")
	if not joined(alpha) or not joined(beta):return false
	var ws:bool=server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and beta.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer
	expect(ws,"server and both clients use WebSocketMultiplayerPeer")
	expect(server.multiplayer.is_server() and not alpha.session.multiplayer.is_server() and not beta.session.multiplayer.is_server(),"one server, two remote clients")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World (snapshots only)")
	expect(alpha.session.own_id!=beta.session.own_id,"distinct tokens give distinct public ids")
	await settle([alpha,beta])
	print("RESIDENT_BOND_SESSION_LABEL machine=single process=single transport=%s loopback=127.0.0.1:%d clients=2(+late joiner,+picnic-less run) fixture=SEEDED(picnic,time=%.0f,positions,bags) clock=Engine.time_scale %.0fx for the day boundary shutdown=normal-only(not crash durability)"%["websocket" if ws else "UNEXPECTED",port,START_TIME,TIME_SCALE])
	print("RESIDENT_BOND_SESSION_CELLS luoluo=%s lingpopo=%s (picnic-less luoluo=%s lingpopo=%s) from World.bond_place"%[str(post_cell),str(bell_cell),str(lock_post_cell),str(lock_bell_cell)])
	var ARU:=aru_cell
	var RANCH:=ranch_cell

	# 1. Fresh, private views.
	for c:Client in [alpha,beta]:
		var other:Client=beta if c==alpha else alpha
		expect(c.region()==Regions.HOME,"%s starts at home (seeded)"%c.label)
		expect(Bond.day(c.clock())==START_DAY,"%s's snapshot clock is on world day %d (%.1f)"%[c.label,START_DAY,c.clock()])
		var keys:Array=c.bonds().keys()
		keys.sort()
		var want:Array=Bond.RESIDENTS.duplicate()
		want.sort()
		expect(keys==want and keys.size()==RESIDENT_COUNT and "luoluo" in keys and "lingpopo" in keys and "diandian" in keys,"%s's resident_bonds lists exactly the twelve residents incl. luoluo, lingpopo and diandian (%s)"%[c.label,str(keys)])
		expect_view(c,{},"case 1 fresh")
		private_check(c,[other],"case 1")
	expect(canon(alpha.bag())==canon(ALPHA_BAG) and canon(beta.bag())==canon(BETA_BAG),"preset bags arrive unchanged in the own snapshots")
	expect(alpha.pos().distance_to(Vector2(ARU)+HALF)<=3.2 and beta.pos().distance_to(Vector2(RANCH)+HALF)<=3.2,"alpha is within reach of aru and beta of mianmian")

	# 2. Alpha talks to aru; beta's view stays at 0; same-day repeat refused.
	var bag_a:=canon(alpha.bag())
	var bag_b:=canon(beta.bag())
	var r:=await act(alpha,"resident_talk",ARU,"aru")
	expect(r.ok and r.message==talk_msg("aru",START_DAY,0,1),"alpha talks to aru over the network (%s)"%r.message)
	await settle([alpha,beta])
	expect_view(alpha,{"aru":[1,true,false]},"case 2 after alpha's talk")
	var aru_row:Dictionary=alpha.bonds().get("aru",{})
	expect(int(aru_row.get("points",-1))==1 and int(aru_row.get("stage",-1))==1 and str(aru_row.get("stage_name",""))=="認識" and aru_row.get("talked_today")==true,"alpha's aru: 1 point, stage 1 認識, talked_today true")
	expect(canon(alpha.bag())==bag_a,"talking leaves alpha's whole bag unchanged")
	expect_view(beta,{},"case 2 beta after alpha's talk (later snapshot)")
	expect(canon(beta.bag())==bag_b,"beta's whole bag unchanged by alpha's talk")
	private_check(beta,[alpha],"case 2 beta")
	private_check(alpha,[beta],"case 2 alpha")
	await refuse(alpha,"resident_talk",ARU,"aru",talked_msg("aru"),"case 2 alpha's second talk to aru the same day",[beta])
	# Alpha's liked gift to aru (+3 on the same day as the talk).
	bag_a=canon(alpha.bag())
	r=await act(alpha,"resident_gift",ARU,"aru:tea_light")
	expect(r.ok and r.message==liked_msg("aru","tea_light",1,1),"alpha gifts aru a liked tea_light (%s)"%r.message)
	await settle([alpha,beta])
	expect(canon(alpha.bag())==plus(bag_a,{"tea_light":1},-1),"exactly one tea_light left alpha's bag (%s)"%text(canon(alpha.bag())))
	expect_view(alpha,{"aru":[4,true,true]},"case 2 after alpha's tea gift")
	expect(canon(beta.bag())==bag_b,"beta's bag unchanged by alpha's gift")
	expect_view(beta,{},"case 2 beta after alpha's gift")

	# 3. Beta gifts mianmian (liked +3); alpha untouched; same-day second gift accepted without points.
	bag_a=canon(alpha.bag())
	bag_b=canon(beta.bag())
	r=await act(beta,"resident_gift",RANCH,"mianmian:feed")
	expect(r.ok and r.message==liked_msg("mianmian","feed",0,1),"beta gifts mianmian a liked feed (%s)"%r.message)
	await settle([alpha,beta])
	expect(canon(beta.bag())==plus(bag_b,{"feed":1},-1),"exactly one feed left beta's bag (%s)"%text(canon(beta.bag())))
	expect_view(beta,{"mianmian":[3,false,true]},"case 3 after beta's liked gift")
	expect(canon(alpha.bag())==bag_a,"alpha's whole bag unchanged by beta's gift")
	expect_view(alpha,{"aru":[4,true,true]},"case 3 alpha after beta's gift")
	private_check(alpha,[beta],"case 3 alpha")
	bag_b=canon(beta.bag())
	r=await act(beta,"resident_gift",RANCH,"mianmian:radish")
	expect(r.ok and r.message==repeat_gift_msg("mianmian","radish"),"beta's same-day second gift (radish) is accepted without points (%s)"%r.message)
	await settle([alpha,beta])
	expect(canon(beta.bag())==plus(bag_b,{"radish":1},-1),"the second gift removed exactly one radish (%s)"%text(canon(beta.bag())))
	expect_view(beta,{"mianmian":[3,false,true]},"case 3 after beta's second gift")
	expect(canon(alpha.bag())==bag_a,"alpha's bag still unchanged")

	# 6. Replay of the same sequence number (raw request_action RPC) is dropped.
	expect(beta.session.counter==int(r.sequence),"beta's last used sequence is the second gift's")
	bag_b=canon(beta.bag())
	var view_b:=text(rows(beta.bonds()))
	var marks:=[alpha.notices.size(),beta.notices.size()]
	beta.session.request_action.rpc_id(1,int(r.sequence),"resident_gift",RANCH,"mianmian:radish",beta.region(),int(beta.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(beta.notices.size()==marks[1] and alpha.notices.size()==marks[0],"re-sent identical gift request (same sequence) gets no notice")
	expect(canon(beta.bag())==bag_b and text(rows(beta.bonds()))==view_b,"re-sent gift removes no second radish and adds no points")
	expect_view(alpha,{"aru":[4,true,true]},"case 6 alpha after beta's replay")

	# 4. Rejections, each compared on both clients' whole bags and views.
	await refuse(alpha,"resident_gift",ARU,"aru:wood",keep_msg("aru"),"case 4 alpha gifts non-giftable wood to aru",[beta])
	await refuse(alpha,"resident_gift",ARU,"aru:milk",missing_msg("milk"),"case 4 alpha gifts milk she does not hold",[beta])
	await refuse(beta,"resident_gift",RANCH,"mianmian:wood",keep_msg("mianmian"),"case 4 beta gifts non-giftable wood to mianmian",[alpha])
	await refuse(beta,"resident_gift",RANCH,"mianmian:wool_cloth",missing_msg("wool_cloth"),"case 4 beta gifts wool_cloth she does not hold",[alpha])
	await refuse(beta,"resident_talk",RANCH+Vector2i.RIGHT,"mianmian",MSG_PLACE,"case 4 beta's talk aimed at the cell beside mianmian",[alpha])
	await refuse(beta,"resident_talk",RANCH,"aru",MSG_PLACE,"case 4 beta's talk to aru aimed at mianmian's cell",[alpha])
	await refuse(alpha,"resident_talk",RANCH,"mianmian",MSG_FAR,"case 4 alpha talks to mianmian from aru's side (%.1f tiles)"%alpha.pos().distance_to(Vector2(RANCH)+HALF),[beta])
	await refuse(alpha,"resident_talk",ARU,"tom",MSG_PLACE,"case 4 talk to a resident id that does not exist",[beta])
	await refuse(beta,"resident_gift",RANCH,"nobody:radish",MSG_PLACE,"case 4 gift to a resident id that does not exist",[alpha])
	expect_view(alpha,{"aru":[4,true,true]},"case 4 alpha after all refusals")
	expect_view(beta,{"mianmian":[3,false,true]},"case 4 beta after all refusals")

	# 5. Alpha walks to the ranch; both talk to mianmian in the same client frame.
	expect(await walk(alpha,to_ranch,15.0),"alpha walks from aru to the ranch over the network")
	expect(alpha.pos().distance_to(Vector2(RANCH)+HALF)<=3.2,"alpha now stands within reach of mianmian (%s)"%str(alpha.pos()))
	await settle([alpha,beta])
	bag_a=canon(alpha.bag())
	bag_b=canon(beta.bag())
	marks=[alpha.notices.size(),beta.notices.size()]
	var frame:=Engine.get_process_frames()
	var seq_a:int=alpha.session.perform("resident_talk",RANCH,"mianmian")
	var seq_b:int=beta.session.perform("resident_talk",RANCH,"mianmian")
	expect(Engine.get_process_frames()==frame and seq_a>0 and seq_b>0,"both talks issued in the same client frame")
	var both:=await wait_until(func():return alpha.notices.size()>int(marks[0]) and beta.notices.size()>int(marks[1]),4.0)
	expect(both,"both simultaneous talks are answered")
	if both:
		var na:Array=alpha.notices[int(marks[0])]
		var nb:Array=beta.notices[int(marks[1])]
		expect(bool(na[1]) and str(na[0])==talk_msg("mianmian",START_DAY,0,1),"alpha's simultaneous talk succeeds with her own first stage-up (%s)"%str(na[0]))
		expect(bool(nb[1]) and str(nb[0])==talk_msg("mianmian",START_DAY,1,1),"beta's simultaneous talk succeeds without a stage-up (%s)"%str(nb[0]))
	await settle([alpha,beta])
	expect_view(alpha,{"aru":[4,true,true],"mianmian":[1,true,false]},"case 5 alpha after the simultaneous talk")
	expect_view(beta,{"mianmian":[4,true,true]},"case 5 beta after the simultaneous talk")
	expect(canon(alpha.bag())==bag_a and canon(beta.bag())==bag_b,"simultaneous talks leave both bags unchanged")

	# 7. Alpha disconnects and rejoins.
	var view_a:=text(rows(alpha.bonds()))
	view_b=text(rows(beta.bonds()))
	bag_a=canon(alpha.bag())
	await leave(alpha)
	expect(await wait_until(func():return int(beta.session.snapshot.get("room_population",0))==1,4.0),"server sees alpha leave (room population 1)")
	await settle([beta])
	expect(text(rows(beta.bonds()))==view_b and canon(beta.bag())==bag_b,"beta's view and bag unchanged while alpha is away")
	alpha=await join("alpha",ALPHA,port)
	expect(joined(alpha),"alpha rejoins with the same token")
	if not joined(alpha):return false
	await settle([alpha,beta])
	expect(text(rows(alpha.bonds()))==view_a,"alpha's whole resident_bonds view is intact after rejoin")
	expect(canon(alpha.bag())==bag_a and alpha.pos().distance_to(Vector2(RANCH)+HALF)<=3.2,"alpha's bag and ranch position intact after rejoin")
	expect(text(rows(beta.bonds()))==view_b and canon(beta.bag())==bag_b,"beta unaffected by alpha's rejoin")
	private_check(alpha,[beta],"case 7 alpha after rejoin")
	await refuse(alpha,"resident_talk",RANCH,"mianmian",talked_msg("mianmian"),"case 7 alpha's repeat mianmian talk from a fresh connection",[beta])

	# 11. Fifth batch (picnic done, still world day 2). Nothing below is preset:
	# both walks, talks, gifts, refusals and the replay go over the network.
	var POST:=post_cell
	var BELL:=bell_cell
	var view_a5:={"aru":[4,true,true],"mianmian":[1,true,false]}
	var view_b5:={"mianmian":[4,true,true]}
	expect(await walk(alpha,to_post,15.0),"case 11 alpha walks from the ranch to luoluo over the network")
	expect(alpha.pos().distance_to(Vector2(POST)+HALF)<=3.2,"case 11 alpha stands within reach of luoluo %s (%s)"%[str(POST),str(alpha.pos())])
	expect(await walk(beta,to_bell,15.0),"case 11 beta walks from the ranch to lingpopo over the network")
	expect(beta.pos().distance_to(Vector2(BELL)+HALF)<=3.2,"case 11 beta stands within reach of lingpopo %s (%s)"%[str(BELL),str(beta.pos())])
	await settle([alpha,beta])
	expect_view(alpha,view_a5,"case 11 alpha before the fifth-batch actions")
	expect_view(beta,view_b5,"case 11 beta before the fifth-batch actions")
	# 11a. Alpha talks to luoluo: +1 for alpha only.
	bag_a=canon(alpha.bag())
	bag_b=canon(beta.bag())
	r=await act(alpha,"resident_talk",POST,"luoluo")
	expect(r.ok and r.message==talk_msg("luoluo",START_DAY,0,1),"case 11 alpha talks to luoluo over the network (%s)"%r.message)
	await settle([alpha,beta])
	view_a5["luoluo"]=[1,true,false]
	expect_view(alpha,view_a5,"case 11 alpha after her luoluo talk")
	expect(canon(alpha.bag())==bag_a,"case 11 talking to luoluo leaves alpha's whole bag unchanged")
	expect_view(beta,view_b5,"case 11 beta after alpha's luoluo talk (luoluo still 0 for beta)")
	expect(canon(beta.bag())==bag_b,"case 11 beta's whole bag unchanged by alpha's luoluo talk")
	private_check(beta,[alpha],"case 11 beta after alpha's luoluo talk")
	private_check(alpha,[beta],"case 11 alpha after her luoluo talk")
	await refuse(alpha,"resident_talk",POST,"luoluo",talked_msg("luoluo"),"case 11 alpha's second luoluo talk the same day",[beta])
	# 11b. Beta gives lingpopo a liked soup: +3 for beta only, exactly one soup.
	bag_a=canon(alpha.bag())
	bag_b=canon(beta.bag())
	expect(Bond.liked("lingpopo","soup"),"soup is in RESIDENT_BOND.LIKES for lingpopo")
	r=await act(beta,"resident_gift",BELL,"lingpopo:soup")
	expect(r.ok and r.message==liked_msg("lingpopo","soup",0,1),"case 11 beta gifts lingpopo a liked soup (%s)"%r.message)
	await settle([alpha,beta])
	expect(canon(beta.bag())==plus(bag_b,{"soup":1},-1),"case 11 exactly one soup left beta's bag (%s)"%text(canon(beta.bag())))
	view_b5["lingpopo"]=[3,false,true]
	expect_view(beta,view_b5,"case 11 beta after her lingpopo gift")
	expect(canon(alpha.bag())==bag_a,"case 11 alpha's whole bag unchanged by beta's lingpopo gift")
	expect_view(alpha,view_a5,"case 11 alpha after beta's lingpopo gift (lingpopo still 0 for alpha)")
	private_check(alpha,[beta],"case 11 alpha after beta's lingpopo gift")
	private_check(beta,[alpha],"case 11 beta after her lingpopo gift")
	# 11c. Replay of the liked-gift sequence (raw request_action RPC): beta still
	# holds one soup, so a processed replay would deduct it; it must be dropped.
	expect(beta.session.counter==int(r.sequence),"case 11 beta's last used sequence is the lingpopo gift's")
	bag_b=canon(beta.bag())
	var view_b11:=text(rows(beta.bonds()))
	marks=[alpha.notices.size(),beta.notices.size()]
	beta.session.request_action.rpc_id(1,int(r.sequence),"resident_gift",BELL,"lingpopo:soup",beta.region(),int(beta.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(beta.notices.size()==marks[1] and alpha.notices.size()==marks[0],"case 11 re-sent lingpopo gift (same sequence) gets no notice")
	expect(canon(beta.bag())==bag_b and int(bag_b.get("soup",0))==1 and text(rows(beta.bonds()))==view_b11,"case 11 re-sent lingpopo gift deducts no soup and adds no points")
	expect_view(alpha,view_a5,"case 11 alpha after beta's replay")
	# 11d. Same-day repeat gift: the soup is consumed, no points.
	bag_b=canon(beta.bag())
	r=await act(beta,"resident_gift",BELL,"lingpopo:soup")
	expect(r.ok and r.message==repeat_gift_msg("lingpopo","soup"),"case 11 beta's same-day second lingpopo gift is accepted without points (%s)"%r.message)
	await settle([alpha,beta])
	expect(canon(beta.bag())==plus(bag_b,{"soup":1},-1),"case 11 the repeat gift removed exactly one soup (%s)"%text(canon(beta.bag())))
	expect_view(beta,view_b5,"case 11 beta after the repeat lingpopo gift (still 3)")
	expect(canon(alpha.bag())==bag_a,"case 11 alpha's bag still unchanged")
	# 11e. Refusals, both ends' whole bags and views unchanged.
	await refuse(alpha,"resident_talk",post_wrong,"luoluo",MSG_PLACE,"case 11 alpha's luoluo talk aimed at the neighbour cell %s"%str(post_wrong),[beta])
	await refuse(beta,"resident_gift",bell_wrong,"lingpopo:radish",MSG_PLACE,"case 11 beta's lingpopo gift aimed at the neighbour cell %s"%str(bell_wrong),[alpha])
	await refuse(beta,"resident_talk",BELL,"luoluo",MSG_PLACE,"case 11 beta's luoluo talk aimed at lingpopo's cell",[alpha])
	await refuse(alpha,"resident_talk",BELL,"lingpopo",MSG_FAR,"case 11 alpha talks to lingpopo from luoluo's side (%.1f tiles)"%alpha.pos().distance_to(Vector2(BELL)+HALF),[beta])
	await refuse(alpha,"resident_gift",POST,"luoluo:bread",missing_msg("bread"),"case 11 alpha gifts luoluo bread she does not hold",[beta])
	await refuse(beta,"resident_gift",BELL,"lingpopo:carrot_soup",missing_msg("carrot_soup"),"case 11 beta gifts lingpopo carrot_soup she does not hold",[alpha])
	await refuse(beta,"resident_gift",BELL,"lingpopo:soup",missing_msg("soup"),"case 11 beta gifts lingpopo soup after both were used up",[alpha])
	await refuse(alpha,"resident_gift",POST,"luoluo:wood",keep_msg("luoluo"),"case 11 alpha gifts non-giftable wood to luoluo",[beta])
	await refuse(beta,"resident_gift",BELL,"lingpopo:wood",keep_msg("lingpopo"),"case 11 beta gifts non-giftable wood to lingpopo",[alpha])
	expect_view(alpha,view_a5,"case 11 alpha after all fifth-batch refusals")
	expect_view(beta,view_b5,"case 11 beta after all fifth-batch refusals")
	expect(canon(beta.bag())==canon({"feed":2,"wool":1,"radish":1,"wood":5}),"case 11 beta's bag after the fifth batch (%s)"%text(canon(beta.bag())))

	# 8. Walk back to aru (from luoluo, after case 11), cross the day boundary, talk again.
	expect(await walk(alpha,post_to_aru,15.0),"alpha walks back from luoluo to aru")
	expect(alpha.pos().distance_to(Vector2(ARU)+HALF)<=3.2,"alpha stands within reach of aru again (%s)"%str(alpha.pos()))
	expect(Bond.day(alpha.clock())==START_DAY and Bond.day(beta.clock())==START_DAY,"guard: still world day %d before the fast-forward (time %.1f)"%[START_DAY,alpha.clock()])
	await refuse(alpha,"resident_talk",ARU,"aru",talked_msg("aru"),"case 8 alpha's aru talk still refused before the boundary",[beta])
	var crossed:=await fast_forward(func():
		var e=alpha.bonds().get("aru",{})
		return Bond.day(alpha.clock())>=START_DAY+1 and e is Dictionary and e.get("talked_today")==false,20.0)
	expect(crossed,"world day %d begins on the live server clock (time scale %.0fx)"%[START_DAY+1,TIME_SCALE])
	await settle([alpha,beta])
	expect(Bond.day(alpha.clock())==START_DAY+1 and Bond.day(beta.clock())==START_DAY+1,"both snapshots are on world day %d (time %.1f)"%[START_DAY+1,alpha.clock()])
	expect_view(alpha,{"aru":[4,false,false],"mianmian":[1,false,false],"luoluo":[1,false,false]},"case 8 alpha after the boundary (daily flags reset, points kept, incl. luoluo)")
	expect_view(beta,{"mianmian":[4,false,false],"lingpopo":[3,false,false]},"case 8 beta after the boundary (incl. lingpopo)")
	var lu=alpha.bonds().get("luoluo",{})
	var li=beta.bonds().get("lingpopo",{})
	expect(lu is Dictionary and int(lu.get("points",-1))==1 and lu.get("talked_today")==false and lu.get("gifted_today")==false,"case 8 alpha's luoluo: 1 point kept, talked_today reset to false")
	expect(li is Dictionary and int(li.get("points",-1))==3 and li.get("talked_today")==false and li.get("gifted_today")==false,"case 8 beta's lingpopo: 3 points kept, gifted_today reset to false")
	bag_a=canon(alpha.bag())
	r=await act(alpha,"resident_talk",ARU,"aru")
	expect(r.ok and r.message==talk_msg("aru",START_DAY+1,1,1),"alpha's next-day aru talk succeeds (%s)"%r.message)
	await settle([alpha,beta])
	expect_view(alpha,{"aru":[5,true,false],"mianmian":[1,false,false],"luoluo":[1,false,false]},"case 8 alpha after the next-day talk")
	expect_view(beta,{"mianmian":[4,false,false],"lingpopo":[3,false,false]},"case 8 beta after alpha's next-day talk")
	expect(canon(alpha.bag())==bag_a,"next-day talk leaves alpha's bag unchanged")

	# 9. Normal shutdown, exact save, restart, rejoin, late joiner.
	await settle([alpha,beta])
	var final_views:={ALPHA:text(rows(alpha.bonds())),BETA:text(rows(beta.bonds()))}
	var final_bags:={ALPHA:canon(alpha.bag()),BETA:canon(beta.bag())}
	expect(final_bags[ALPHA]==canon({"radish":2,"wood":5}) and final_bags[BETA]==canon({"feed":2,"wool":1,"radish":1,"wood":5}),"final bags: alpha %s, beta %s"%[text(final_bags[ALPHA]),text(final_bags[BETA])])
	await leave(alpha)
	await leave(beta)
	expect(await stop_server(),"server Session shuts down with a final save")
	var disk=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	expect(disk is Dictionary,"save file parses")
	if not disk is Dictionary:return false
	expect(Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"saved world passes SaveSchema")
	var want_a:={"aru":rec(5,START_DAY+1,START_DAY),"mianmian":rec(1,START_DAY,-1),"luoluo":rec(1,START_DAY,-1)}
	var want_b:={"mianmian":rec(4,START_DAY,START_DAY),"lingpopo":rec(3,-1,START_DAY)}
	var got_a=disk_bonds(disk.players.get(ALPHA,{}))
	var got_b=disk_bonds(disk.players.get(BETA,{}))
	expect(text(got_a)==text(want_a),"save holds alpha's exact bonds %s (got %s)"%[text(want_a),text(got_a)])
	expect(text(got_b)==text(want_b),"save holds beta's exact bonds %s (got %s)"%[text(want_b),text(got_b)])
	if got_a is Dictionary and got_b is Dictionary:
		expect(text(got_a.get("luoluo"))==text(rec(1,START_DAY,-1)) and not got_a.has("lingpopo"),"save: alpha luoluo {points 1, talk_day %d, gift_day -1}, no lingpopo record"%START_DAY)
		expect(text(got_b.get("lingpopo"))==text(rec(3,-1,START_DAY)) and not got_b.has("luoluo"),"save: beta lingpopo {points 3, talk_day -1, gift_day %d}, no luoluo record"%START_DAY)
	for token in [ALPHA,BETA]:
		expect(canon(disk.players.get(token,{}).get("inventory",{}))==final_bags[token],"save holds %s's exact bag"%token)
	var port2:=start_server()
	expect(port2>0,"a new server Session hosts the same save")
	if port2==0:return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	expect(joined(alpha) and joined(beta),"both clients rejoin the restarted server")
	if not joined(alpha) or not joined(beta):return false
	await settle([alpha,beta])
	expect(Bond.day(alpha.clock())==START_DAY+1,"restarted world is still on day %d"%(START_DAY+1))
	expect(text(rows(alpha.bonds()))==final_views[ALPHA],"alpha's whole view identical after restart")
	expect(text(rows(beta.bonds()))==final_views[BETA],"beta's whole view identical after restart")
	expect(canon(alpha.bag())==final_bags[ALPHA] and canon(beta.bag())==final_bags[BETA],"both bags identical after restart")
	await refuse(alpha,"resident_talk",ARU,"aru",talked_msg("aru"),"case 9 alpha's same-day aru talk after restart",[beta])
	gamma=await join("gamma",GAMMA,port2)
	expect(joined(gamma),"late joiner gamma joins with a fresh token")
	if not joined(gamma):return false
	await settle([alpha,beta,gamma])
	expect_view(gamma,{},"case 9 late joiner")
	var gkeys:Array=gamma.bonds().keys()
	expect(gkeys.size()==RESIDENT_COUNT and "luoluo" in gkeys and "lingpopo" in gkeys and "diandian" in gkeys,"case 9 late joiner sees all twelve residents at 0 (%s)"%str(gkeys))
	expect(int(alpha.bonds().get("luoluo",{}).get("points",-1))==1 and int(beta.bonds().get("lingpopo",{}).get("points",-1))==3 and int(alpha.bonds().get("lingpopo",{}).get("points",-1))==0 and int(beta.bonds().get("luoluo",{}).get("points",-1))==0,"case 9 after restart: alpha luoluo 1 / lingpopo 0, beta lingpopo 3 / luoluo 0")
	private_check(gamma,[alpha,beta],"case 9 gamma")
	private_check(alpha,[beta,gamma],"case 9 alpha")
	expect(text(rows(alpha.bonds()))==final_views[ALPHA] and text(rows(beta.bonds()))==final_views[BETA],"gamma's arrival changes neither alpha's nor beta's view")
	await leave(gamma)
	gamma=null
	await leave(alpha)
	await leave(beta)
	expect(await stop_server(),"restarted server shuts down cleanly")

	# 10. Picnic-less variant: mianmian is not at the ranch yet.
	save_path=folder.path_join("locked.json")
	# PRESET here: picnic=false, time, and the positions/bags of delta, epsilon
	# (beside luoluo's cell) and zeta (beside lingpopo's cell); no bonds.
	if not expect(seed_world(save_path,false,{DELTA:{"name":"delta","at":lock_stand,"inv":DELTA_BAG},
			EPSILON:{"name":"epsilon","at":lock_post_stand,"inv":EPSILON_BAG},ZETA:{"name":"zeta","at":lock_bell_stand,"inv":ZETA_BAG},
			ETA:{"name":"eta","at":Vector2(Bond.GARDEN_CELL)+Vector2(0.5,1.5),"inv":ETA_BAG,"region":GARDEN_REGION},
			THETA:{"name":"theta","at":THETA_AT,"inv":THETA_BAG,"region":GARDEN_REGION}}),"picnic-less fixture written and accepted by SaveSchema"):return false
	var port3:=start_server()
	expect(port3>0,"picnic-less server hosts")
	if port3==0:return false
	delta=await join("delta",DELTA,port3)
	expect(joined(delta),"delta joins the picnic-less world")
	if not joined(delta):return false
	expect(delta.session.snapshot.get("picnic")==false,"delta's snapshot carries picnic=false")
	expect_view(delta,{},"case 10 delta fresh")
	await refuse(delta,"resident_talk",RANCH,"mianmian",Bond.RANCH_LOCKED,"case 10 talk to mianmian before the picnic",[])
	await refuse(delta,"resident_gift",RANCH,"mianmian:feed",Bond.RANCH_LOCKED,"case 10 liked gift to mianmian before the picnic",[])
	# achao: the fixture never repairs the dock (dock_stage stays 0).
	expect(delta.pos().distance_to(Vector2(dock_cell)+HALF)<=3.2,"delta stands within reach of achao's dock cell %s (%s)"%[str(dock_cell),str(delta.pos())])
	await refuse(delta,"resident_talk",dock_cell,"achao",Bond.DOCK_LOCKED,"case 10 talk to achao before the dock is repaired",[])
	await refuse(delta,"resident_gift",dock_cell,"achao:radish",Bond.DOCK_LOCKED,"case 10 common gift to achao before the dock is repaired",[])
	expect(canon(delta.bag())==canon(DELTA_BAG),"delta keeps the exact preset bag")
	# 10b. Fifth batch before the picnic: luoluo and lingpopo refuse with the
	# exact locked text (the cells come from World.bond_place on this world).
	epsilon=await join("epsilon",EPSILON,port3)
	zeta=await join("zeta",ZETA,port3)
	expect(joined(epsilon) and joined(zeta),"epsilon and zeta join the picnic-less world")
	if not joined(epsilon) or not joined(zeta):return false
	await settle([delta,epsilon,zeta])
	for c:Client in [epsilon,zeta]:
		expect(c.bonds().size()==RESIDENT_COUNT,"case 10b %s sees twelve residents"%c.label)
		expect_view(c,{},"case 10b %s fresh"%c.label)
	expect(epsilon.pos().distance_to(Vector2(lock_post_cell)+HALF)<=3.2 and zeta.pos().distance_to(Vector2(lock_bell_cell)+HALF)<=3.2,"case 10b epsilon within reach of luoluo %s, zeta of lingpopo %s"%[str(lock_post_cell),str(lock_bell_cell)])
	await refuse(epsilon,"resident_talk",lock_post_cell,"luoluo",Bond.POST_LOCKED,"case 10b talk to luoluo before the picnic",[delta,zeta])
	await refuse(epsilon,"resident_gift",lock_post_cell,"luoluo:bread",Bond.POST_LOCKED,"case 10b liked bread gift to luoluo before the picnic",[delta,zeta])
	await refuse(zeta,"resident_talk",lock_bell_cell,"lingpopo",Bond.BELL_LOCKED,"case 10b talk to lingpopo before the picnic",[delta,epsilon])
	await refuse(zeta,"resident_gift",lock_bell_cell,"lingpopo:soup",Bond.BELL_LOCKED,"case 10b liked soup gift to lingpopo before the picnic",[delta,epsilon])
	expect(canon(epsilon.bag())==canon(EPSILON_BAG) and canon(zeta.bag())==canon(ZETA_BAG),"case 10b epsilon and zeta keep their exact preset bags")
	# 10c. Sixth batch: diandian in star_garden has no gate, even before the picnic.
	var GARDEN:=Bond.GARDEN_CELL
	var garden_place:Array=World.bond_place({},"diandian")
	expect(str(garden_place[0])==GARDEN_REGION and garden_place[1]==GARDEN,"case 10c diandian's bond_place is star_garden %s"%str(GARDEN))
	eta=await join("eta",ETA,port3)
	theta=await join("theta",THETA,port3)
	expect(joined(eta) and joined(theta),"case 10c eta and theta join the picnic-less world in star_garden")
	if not joined(eta) or not joined(theta):return false
	await settle([eta,theta])
	expect(eta.region()==GARDEN_REGION and theta.region()==GARDEN_REGION,"case 10c eta and theta are in star_garden (%s / %s)"%[eta.region(),theta.region()])
	expect(eta.pos().distance_to(Vector2(GARDEN)+HALF)<=3.2,"case 10c eta stands within reach of diandian %s (%s)"%[str(GARDEN),str(eta.pos())])
	expect(theta.pos().distance_to(Vector2(GARDEN)+HALF)>3.2,"case 10c theta stands out of reach of diandian (%s)"%str(theta.pos()))
	for c:Client in [eta,theta]:
		expect(c.bonds().size()==RESIDENT_COUNT and c.bonds().has("diandian"),"case 10c %s sees twelve residents incl. diandian"%c.label)
		expect_view(c,{},"case 10c %s fresh"%c.label)
	await refuse(eta,"resident_talk",GARDEN+Vector2i.RIGHT,"diandian",MSG_PLACE,"case 10c eta's diandian talk aimed at the cell east of her",[theta])
	await refuse(eta,"resident_talk",GARDEN,"nuannuan",MSG_PLACE,"case 10c eta's nuannuan talk aimed at diandian's garden cell",[theta])
	await refuse(theta,"resident_talk",GARDEN,"diandian",MSG_FAR,"case 10c theta talks to diandian from %s"%str(theta.pos()),[eta])
	var theta_cell:=Vector2i(floori(THETA_AT.x),floori(THETA_AT.y))-Vector2i(0,1)
	await refuse(theta,"resident_talk",theta_cell,"diandian",MSG_PLACE,"case 10c theta's diandian talk aimed at the wrong cell %s beside herself"%str(theta_cell),[eta])
	var bag_e:=canon(eta.bag())
	var garden_day:=Bond.day(eta.clock())
	r=await act(eta,"resident_talk",GARDEN,"diandian")
	expect(r.ok and r.message==talk_msg("diandian",garden_day,0,1),"case 10c eta talks to diandian over the network (%s)"%r.message)
	expect(str(r.message).contains("帽沿底下的顏色"),"case 10c eta's first diandian talk names 帽沿底下的顏色")
	await settle([eta,theta])
	expect_view(eta,{"diandian":[1,true,false]},"case 10c eta after her diandian talk")
	expect_view(theta,{},"case 10c theta after eta's diandian talk (still 0)")
	expect(canon(eta.bag())==bag_e,"case 10c talking leaves eta's whole bag unchanged")
	await refuse(eta,"resident_talk",GARDEN,"diandian",talked_msg("diandian"),"case 10c eta's second diandian talk the same day",[theta])
	r=await act(eta,"resident_gift",GARDEN,"diandian:star_mushroom")
	expect(r.ok and r.message==liked_msg("diandian","star_mushroom",1,1),"case 10c eta gifts diandian a liked star_mushroom (%s)"%r.message)
	await settle([eta,theta])
	expect(canon(eta.bag())==plus(bag_e,{"star_mushroom":1},-1),"case 10c exactly one star_mushroom left eta's bag (%s)"%text(canon(eta.bag())))
	expect_view(eta,{"diandian":[4,true,true]},"case 10c eta after her liked gift")
	expect_view(theta,{},"case 10c theta after eta's gift (still 0)")
	expect(canon(theta.bag())==canon(THETA_BAG),"case 10c theta keeps her exact preset bag")
	private_check(theta,[eta],"case 10c theta")
	private_check(eta,[theta],"case 10c eta")
	await leave(eta)
	await leave(theta)
	eta=null
	theta=null
	await leave(epsilon)
	await leave(zeta)
	epsilon=null
	zeta=null
	await leave(delta)
	delta=null
	expect(await stop_server(),"picnic-less server shuts down with a final save")
	var locked=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	expect(locked is Dictionary and locked.players.has(DELTA) and not locked.players[DELTA].has("bonds"),"picnic-less save writes no bonds key for delta")
	if locked is Dictionary:
		expect(canon(locked.players.get(DELTA,{}).get("inventory",{}))==canon(DELTA_BAG),"picnic-less save keeps delta's exact bag")
		for pair:Array in [[EPSILON,EPSILON_BAG],[ZETA,ZETA_BAG]]:
			var who=locked.players.get(pair[0],null)
			expect(who is Dictionary and not who.has("bonds"),"case 10b picnic-less save writes no bonds key for %s"%pair[0])
			if who is Dictionary:
				expect(canon(who.get("inventory",{}))==canon(pair[1]),"case 10b picnic-less save keeps %s's exact bag"%pair[0])
		var eta_disk=locked.players.get(ETA,null)
		var theta_disk=locked.players.get(THETA,null)
		var eta_bonds=disk_bonds(eta_disk)
		var garden_want:={"diandian":rec(4,garden_day,garden_day)}
		expect(text(eta_bonds)==text(garden_want),"case 10c picnic-less save holds eta's exact diandian bond %s (got %s)"%[text(garden_want),text(eta_bonds)])
		expect(eta_disk is Dictionary and str(eta_disk.get("region",""))==GARDEN_REGION and canon(eta_disk.get("inventory",{}))==canon({"radish":1}),"case 10c save keeps eta in star_garden with {radish 1}")
		expect(theta_disk is Dictionary and not theta_disk.has("bonds") and canon(theta_disk.get("inventory",{}))==canon(THETA_BAG),"case 10c save writes no bonds key for theta and keeps her bag")
	return true

func teardown()->void:
	Engine.time_scale=1.0
	for c in [alpha,beta,gamma,delta,epsilon,zeta,eta,theta]:
		if c!=null and is_instance_valid(c.session) and not c.session.shutting_down:
			c.session.shutdown()
	await pause(0.2)
	if server!=null and is_instance_valid(server) and server.world!=null:
		expect(server.shutdown(),"final server shutdown saves cleanly")
	await pause(0.2)
	for c in [alpha,beta,gamma,delta,epsilon,zeta,eta,theta]:
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
