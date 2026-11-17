extends SceneTree
## T066「一起做的事」(resident_goal) two-client Session acceptance over a real
## dedicated server and real WebSocket clients.
##
## LEVEL: one machine, ONE Godot process. Inside the single SceneTree a real
## dedicated server Session listens on a free 127.0.0.1 port with the WebSocket
## transport; separate client Session nodes (甲 alpha, 乙 beta, late joiner 丙
## gamma) join it over loopback, each in its own branch with its own
## SceneMultiplayer, so every request, notice and snapshot travels the RPC +
## WebSocket path. Clients only read their own received snapshots. The server
## World is READ (alpha's bond_goals; and its live state + each token to build the
## expected resident_goals view, because batch-2 needs rows such as fair_weather
## and festival_done depend on the world state) to prove server and client agree,
## plus the on-disk save after each shutdown. It is WRITTEN after seeding exactly
## once (DIRECT WRITE 2 below).
##
## SEEDED FIXTURE (disclosed PRESET; written to a fresh TEMP folder and validated
## with SaveSchema before the server starts): picnic=true (鈴婆婆 present);
## state.time fixed; state.festival left at Festival.fresh() (round 0); bond points
## written directly (DIRECT WRITE 1): alpha lingpopo {points 24} (stage 4 好友, so
## lingpopo 2, 3 and 4 are open), beta lingpopo {points 14} (stage 3 信任, so
## lingpopo 4 is locked for beta), nobody has
## a milu record; positions: alpha just beside lingpopo's cell, beta just beside
## milu's cell (both cells from World.bond_place on a probe save loaded like the
## server's); exact bags alpha {copper_ingot 5, glass 3, soup 2, radish 1}, beta
## {soup 1, copper_joint 2, glass 2}. No bond_goals are ever preset.
## REAL ACTIONS over the network: every resident_goal request and refusal, the
## raw same-sequence resend, disconnect/rejoin, shutdown and restart.
## DIRECT WRITE 2 (case 5b, disclosed): while the server runs, after alpha's
## lingpopo 4「不用等風來」(needs festival_done) has been refused,
## server.world.state.festival is replaced by one FINISHED round
## {round 1, active false, collected 12, contributors {beta: 12}, started/finished/
## ready/best around the current server time}. No coins are paid for it and the
## 風鈴接力 itself is not played (covered by the festival tests); it only stands in
## for "the island finished a round". The saves written after it pass SaveSchema.
## No world time is advanced on purpose; the only clock dependence is the
## fair_weather needs row (棉棉 4), which is computed from the server's own state
## for the expected view, and the run stays within one world day.
## Replay: the only resend reachable from the Session API is the raw
## `request_action` RPC with the already-used sequence number; Session drops it
## before World sees it (the World request-id receipt is covered by
## test_resident_goal.gd).
## BATCH 3 (紀念小物, keepsakes) — same machine, single process, same loopback
## WebSocket evidence as everything above:
## - lingpopo 3 is a keepsake goal, so alpha's REAL lingpopo 3 completion (case 3)
##   also grants 1 keepsake_lingpopo_kit and writes alpha's private
##   player.bond_keepsakes; its same-sequence resend (case 4) applies once.
## - case 5c: alpha places that kit at home with the normal "build" action on a
##   free cell next to its lingpopo stand (cell picked on the probe world, not on
##   a BELL_CELLS candidate so lingpopo's own cell cannot move); beta sees the
##   object with owner = alpha's public id.
## - case 5d "old save" path, DISCLOSED PRESETS: (DIRECT WRITE 1 also gives alpha
##   milu {points 14} = 信任 in the seeded save, so a milu 3 record is
##   schema-valid); DIRECT WRITE 3 adds bond_goals.milu {"3":"soup"} to alpha's
##   live server record WITHOUT any bond_keepsakes entry (= a goal completed
##   before batch 3); DIRECT WRITE 4/5 set alpha's live server position next to
##   milu (another stand than beta's) and back to the lingpopo stand. No items
##   are charged for the preset milu 3 and its soup is NOT taken. The claim
##   (resident_keepsake) requests and refusals themselves are real actions.
## NOT covered: multiple processes, cross-machine, TLS/wss, latency/packet loss,
## crash durability (only normal shutdowns with a final save).
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const Regions=preload("res://scripts/regions.gd")
const KEY:="resident-goal-session"
const ALPHA:="goal-session-alpha-token-8d21"
const BETA:="goal-session-beta-token-3e7c"
const GAMMA:="goal-session-gamma-token-b604"
const START_TIME:=2.0*1440.0+300.0
const HALF:=Vector2(0.5,0.5)
const ALPHA_BAG:={"copper_ingot":5,"glass":3,"soup":2,"radish":1}
const BETA_BAG:={"soup":1,"copper_joint":2,"glass":2}
## PRESET (DIRECT WRITE 1): milu 14 (信任) for alpha only exists so the batch-3
## "old save" milu 3 record written in case 5d passes SaveSchema (stage reached).
const ALPHA_BONDS:={"lingpopo":{"points":24,"talk_day":-1,"gift_day":-1},"milu":{"points":14,"talk_day":-1,"gift_day":-1}}
const BETA_BONDS:={"lingpopo":{"points":14,"talk_day":-1,"gift_day":-1}}
## World.gd literal: the generic 3.2-tile reach gate.
const MSG_FAR:="靠近一點，才能和它互動"
## resident_goals.gd literals (batch 3).
const KEEPSAKE_SUFFIX:="紀念小物也放進背包了，在家園工坊的「生活」頁可以擺到家園。"
const MSG_NO_KEEPSAKE:="這件事的紀念收在手帳裡，沒有可以領的小物。"
const NO_CELL:=Vector2i(-9999,-9999)

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
	func goals()->Dictionary:
		var v=session.snapshot.get("resident_goals",null)
		return v if v is Dictionary else {}

var checks:=0
var failures:=0
var serial:=0
var folder:=""
var save_path:=""
var server
var server_branch:Node
var finished:=false
var bell_cell:=Vector2i.ZERO
var milu_cell:=Vector2i.ZERO
var alpha_stand:=Vector2.ZERO
var beta_stand:=Vector2.ZERO
var alpha_milu_stand:=Vector2.ZERO
var build_cell:=NO_CELL
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
	# Batch 3 added ~10 networked actions/refusals; the watchdog was raised from 100 s.
	create_timer(180.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("RESIDENT_GOAL_SESSION watchdog fired before completion")
	print("RESIDENT_GOAL_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("RESIDENT_GOAL_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("RESIDENT_GOAL_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("RESIDENT_GOAL_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

static func stand_near(w,cell:Vector2i,skip:Vector2=Vector2.INF)->Vector2:
	for off:Vector2 in [Vector2(0.5,1.5),Vector2(1.5,1.5),Vector2(-0.5,1.5),Vector2(1.5,0.5),Vector2(-0.5,0.5),Vector2(0.5,-0.5)]:
		var at:Vector2=Vector2(cell)+off
		if at!=skip and w.can_stand(at):return at
	return Vector2.ZERO

## Cells and stands are computed on a probe world that went through the same
## save -> load path the server uses (loading picnic saves places the community
## table, which can block a home cell).
func plan()->bool:
	var probe:=folder.path_join("probe.json")
	if not expect(seed_world(probe,{}),"probe fixture saved"):return false
	var w:=World.new()
	if not expect(w.load_world(probe),"probe fixture loads like the server's save"):return false
	var bell_place:Array=World.bond_place(w.state,"lingpopo")
	var milu_place:Array=World.bond_place(w.state,"milu")
	bell_cell=bell_place[1]
	milu_cell=milu_place[1]
	expect(str(bell_place[0])==Regions.HOME and str(milu_place[0])==Regions.HOME,"lingpopo and milu both live in the home region")
	expect(Bond.present(w.state,"lingpopo"),"lingpopo is present on the picnic fixture")
	alpha_stand=stand_near(w,bell_cell)
	beta_stand=stand_near(w,milu_cell)
	for spot:Array in [["alpha at lingpopo",alpha_stand,bell_cell],["beta at milu",beta_stand,milu_cell]]:
		var at:Vector2=spot[1]
		var cell:Vector2i=spot[2]
		if not expect(at!=Vector2.ZERO and at.distance_to(Vector2(cell)+HALF)<=3.2,"%s stand %s is standable and within 3.2 of %s"%[spot[0],str(at),str(cell)]):return false
	# Batch 3: a second stand next to milu for alpha (DIRECT WRITE 4 target), and a
	# free home cell next to alpha's lingpopo stand for placing the keepsake.
	alpha_milu_stand=stand_near(w,milu_cell,beta_stand)
	if not expect(alpha_milu_stand!=Vector2.ZERO and alpha_milu_stand!=beta_stand and alpha_milu_stand.distance_to(Vector2(milu_cell)+HALF)<=3.2,"alpha's milu stand %s is standable, not beta's, within 3.2 of milu"%str(alpha_milu_stand)):return false
	if not expect(alpha_stand.distance_to(Vector2(milu_cell)+HALF)>3.2,"alpha's lingpopo stand is out of reach of milu (%.2f tiles)"%alpha_stand.distance_to(Vector2(milu_cell)+HALF)):return false
	var avoid:Array=Bond.BELL_CELLS.duplicate()
	for resident:String in Bond.RESIDENTS:
		var place:Array=World.bond_place(w.state,resident)
		if str(place[0])==Regions.HOME:avoid.append(place[1])
	for stand:Vector2 in [alpha_stand,beta_stand,alpha_milu_stand]:avoid.append(Vector2i(floori(stand.x),floori(stand.y)))
	build_cell=pick_build_cell(w,alpha_stand,avoid)
	if not expect(build_cell!=NO_CELL,"a free buildable home cell exists within 3.0 of alpha's lingpopo stand (%s)"%str(build_cell)):return false
	return expect(beta_stand.distance_to(Vector2(bell_cell)+HALF)>3.2,"beta's stand is out of reach of lingpopo (%.2f tiles)"%beta_stand.distance_to(Vector2(bell_cell)+HALF))

## First empty, unprotected, non-water, unblocked home cell (no resource, crop,
## object or roof) within 3.0 tiles of `stand`, skipping `avoid`.
static func pick_build_cell(w,stand:Vector2,avoid:Array)->Vector2i:
	var base:=Vector2i(floori(stand.x),floori(stand.y))
	for ring:int in [1,2]:
		for dy in range(-ring,ring+1):
			for dx in range(-ring,ring+1):
				if maxi(absi(dx),absi(dy))!=ring:continue
				var c:Vector2i=base+Vector2i(dx,dy)
				if c in avoid:continue
				if stand.distance_to(Vector2(c)+HALF)>3.0:continue
				var k:String=World.key(c)
				if w.water(c) or w.protected(c) or w.blocked(c) or str(w.resource(c))!="":continue
				if w.state.crops.has(k) or w.state.objects.has(k) or w.state.roofs.has(k):continue
				return c
	return NO_CELL

func seed_world(path:String,people:Dictionary)->bool:
	var w:=World.new()
	w.save_path=path
	w.state["picnic"]=true
	w.state["time"]=START_TIME
	for token:String in people:
		var spec:Dictionary=people[token]
		w.add_player(token,str(spec.name))
		var p:Dictionary=w.state.players[token]
		var at:Vector2=spec.at
		p["x"]=at.x
		p["y"]=at.y
		p["inventory"]=(spec.inv as Dictionary).duplicate()
		p["bonds"]=(spec.bonds as Dictionary).duplicate(true)
	w.active_tokens.clear()
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:return false
	for token:String in people:
		if parsed.players.get(token,{}).has(Goals.RECORD_KEY) or parsed.players.get(token,{}).has(Goals.KEEPSAKE_KEY):return false
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
	await wait_until(func():return not c.session.own_id.is_empty() and not c.me().is_empty() and not c.goals().is_empty(),8.0)
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

# ---------------------------------------------------------------- helpers --

static func canon(d:Variant)->Dictionary:
	var out:={}
	if not d is Dictionary:return {"<invalid>":-1}
	for item in d:
		if int(d[item])!=0:out[str(item)]=int(d[item])
	return out

static func plus(a:Dictionary,b:Dictionary,direction:int=1)->Dictionary:
	var out:=canon(a)
	for item in b:
		out[str(item)]=int(out.get(str(item),0))+direction*int(b[item])
		if int(out[str(item)])==0:out.erase(str(item))
	return out

static func text(d:Variant)->String:
	return JSON.stringify(d,"",true)

## Expected whole resident_goals view for a player with these bonds and this record.
## Batch-2 needs rows (fair_weather, festival_done, own_bed, ...) are read from the
## live server state with that player's token, exactly as Session does; the bonds
## and record come from the test's own model, not from the server.
## `keeps` is the test's own model of player.bond_keepsakes (batch 3); null or {}
## means nothing claimed (every keepsake row claimed=false).
func want_view(bonds:Dictionary,record:Variant,token:String,keeps:Variant=null)->String:
	var person:={"bonds":bonds.duplicate(true)}
	if record is Dictionary:person[Goals.RECORD_KEY]=(record as Dictionary).duplicate(true)
	if keeps is Dictionary and not (keeps as Dictionary).is_empty():person[Goals.KEEPSAKE_KEY]=(keeps as Dictionary).duplicate(true)
	if server==null or not is_instance_valid(server) or server.world==null:return "<no server>"
	return text(Goals.view(person,server.world.state,token))

## The needs rows of one stage of `c`'s own resident_goals ([] when absent).
static func needs_rows(c:Client,resident:String,stage:String)->Array:
	var stages=c.goals().get(resident,{})
	if not stages is Dictionary:return []
	var row=stages.get(stage,{})
	if not row is Dictionary:return []
	var rows=row.get("needs",[])
	return rows if rows is Array else []

static func goal_row(c:Client,resident:String,stage:String)->String:
	var stages=c.goals().get(resident,{})
	return text(stages.get(stage,{}) if stages is Dictionary else {})

func server_goals(token:String)->String:
	if server==null or not is_instance_valid(server) or server.world==null:return "<no server>"
	var p:Dictionary=server.world.state.players.get(token,{})
	return text(p.get(Goals.RECORD_KEY,null))

func server_keeps(token:String)->String:
	if server==null or not is_instance_valid(server) or server.world==null:return "<no server>"
	var p:Dictionary=server.world.state.players.get(token,{})
	return text(p.get(Goals.KEEPSAKE_KEY,null))

func expect_view(c:Client,bonds:Dictionary,record:Variant,label:String,keeps:Variant=null)->bool:
	var got:=text(c.goals())
	var want:=want_view(bonds,record,c.token,keeps)
	return expect(got==want,"%s: %s's whole resident_goals is exactly the expected view (record %s, keepsakes %s, got %s)"%[label,c.label,text(record),text(keeps),got])

## Expected "keepsake" sub-row of a stage in the own summary.
static func keep_row(kind:String,claimed:bool)->Dictionary:
	return {"kind":kind,"item":Goals.keepsake_item(kind),"name":str(Goals.KEEPSAKES[kind].name),"claimed":claimed}

## The object `c` sees on a home cell in its received snapshot ({} when none).
static func seen_object(c:Client,cell:Vector2i)->Dictionary:
	var objs=c.session.snapshot.get("objects",{})
	if not objs is Dictionary:return {}
	var o=objs.get(World.key(cell),null)
	return o if o is Dictionary else {}

static func success_msg(resident:String,stage:int)->String:
	var e:Dictionary=Goals.goal(resident,stage)
	var quote:Array=e.quote
	var message:="%s：「%s」你們一起完成了〈%s〉，手帳記下紀念「%s」。"%[Bond.name_of(resident),str(quote[0]),str(e.title),str(e.keepsake)]
	if not Goals.keepsake_kind(resident,stage).is_empty():message+=KEEPSAKE_SUFFIX
	return message

static func claim_msg(resident:String,kind:String)->String:
	return "%s把紀念小物「%s」交給你，已放進背包。在家園工坊的「生活」頁選它就能擺到家園。"%[Bond.name_of(resident),str(Goals.KEEPSAKES[kind].name)]

static func claimed_msg(kind:String)->String:
	return "「%s」已經領過了。"%str(Goals.KEEPSAKES[kind].name)

static func not_done_msg(resident:String,stage:int)->String:
	return "先和%s一起完成〈%s〉，才有紀念小物。"%[Bond.name_of(resident),str(Goals.goal(resident,stage).title)]

## DISCLOSED DIRECT WRITE of a live server position (same region, no travel);
## waits until `c`'s own snapshot shows it.
func teleport(c:Client,at:Vector2,label:String)->bool:
	var live:Dictionary=server.world.state.players[c.token]
	live["x"]=at.x
	live["y"]=at.y
	var seen:=await wait_until(func():return c.pos().distance_to(at)<0.01,3.0)
	await settle([c])
	return expect(seen,"%s: %s's own snapshot shows the preset position %s (got %s)"%[label,c.label,str(at),str(c.pos())])

static func done_msg(resident:String,stage:int)->String:
	return "〈%s〉已經一起完成了，手帳可以重看。"%str(Goals.goal(resident,stage).title)

static func order_msg(resident:String)->String:
	return "順序不太對。%s說不急，再看一次圖示。"%Bond.name_of(resident)

static func stage_msg(resident:String,stage:int)->String:
	return "和%s的關係到「%s」之後，才能一起做這件事。"%[Bond.name_of(resident),Bond.stage_name(stage)]

## Exact refusal; whole bag and whole resident_goals view unchanged for the actor
## and every watcher, and the actor's server-side record unchanged.
func refuse(c:Client,action:String,p:Vector2i,extra:String,message:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var bags:Array=everyone.map(func(x):return canon(x.bag()))
	var views:Array=everyone.map(func(x):return text(x.goals()))
	var on_server:=server_goals(c.token)
	var keeps_on_server:=server_keeps(c.token)
	var r:=await act(c,action,p,extra)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	var same:=true
	for i in everyone.size():
		if canon(everyone[i].bag())!=bags[i] or text(everyone[i].goals())!=views[i]:same=false
	expect(same,"%s: every bag and every resident_goals view unchanged in all watching snapshots"%label)
	expect(server_goals(c.token)==on_server,"%s: the server-side bond_goals of %s is unchanged"%[label,c.label])
	expect(server_keeps(c.token)==keeps_on_server,"%s: the server-side bond_keepsakes of %s is unchanged"%[label,c.label])

## Privacy of `c`'s received snapshot with respect to `others`.
func private_check(c:Client,others:Array,label:String)->void:
	var people=c.session.snapshot.get("players",{})
	for o:Client in others:
		var them=people.get(o.session.own_id,null) if people is Dictionary else null
		expect(them is Dictionary and not them.has(Goals.RECORD_KEY) and not them.has(Goals.KEEPSAKE_KEY) and not them.has("resident_goals"),"%s: %s's snapshot entry for %s exists and has no bond_goals / bond_keepsakes / resident_goals"%[label,c.label,o.label])
	expect(not c.me().has(Goals.RECORD_KEY) and not c.me().has(Goals.KEEPSAKE_KEY),"%s: %s's own player entry carries no raw bond_goals / bond_keepsakes record"%[label,c.label])
	var dump:=JSON.stringify(c.session.snapshot)
	expect(not dump.contains("\"%s\""%Goals.RECORD_KEY),"%s: %s's whole snapshot never names bond_goals"%[label,c.label])
	expect(not dump.contains("\"%s\""%Goals.KEEPSAKE_KEY),"%s: %s's whole snapshot never names bond_keepsakes"%[label,c.label])
	expect(dump.count("\"resident_goals\"")==1,"%s: %s's snapshot carries exactly one resident_goals (its own)"%[label,c.label])
	var leaked:=false
	for o:Client in others+[c]:
		if dump.contains(o.token):leaked=true
	expect(not leaked,"%s: %s's snapshot contains no private token"%[label,c.label])

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("resident-goal-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	if not plan():return false
	save_path=folder.path_join("world.json")
	var seeded:=seed_world(save_path,{ALPHA:{"name":"alpha","at":alpha_stand,"inv":ALPHA_BAG,"bonds":ALPHA_BONDS},BETA:{"name":"beta","at":beta_stand,"inv":BETA_BAG,"bonds":BETA_BONDS}})
	if not expect(seeded,"SEEDED FIXTURE (picnic, time, positions, bags, bond points; no bond_goals) accepted by SaveSchema.validate"):return false
	var port:=start_server()
	expect(port>0,"server Session hosts on 127.0.0.1 with the websocket transport")
	if port==0:return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback and received their own snapshot")
	if not joined(alpha) or not joined(beta):return false
	var ws:bool=server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and beta.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer
	expect(ws,"server and both clients use WebSocketMultiplayerPeer")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World (snapshots only)")
	await settle([alpha,beta])
	print("RESIDENT_GOAL_SESSION_LABEL machine=single process=single transport=%s loopback=127.0.0.1:%d clients=2(+late joiner) fixture=SEEDED(picnic,time,positions,bags,bond points) lingpopo=%s milu=%s shutdown=normal-only"%["websocket" if ws else "UNEXPECTED",port,str(bell_cell),str(milu_cell)])
	var BELL:=bell_cell
	var MILU:=milu_cell
	var alpha_record:Dictionary={}
	# Test-side model of alpha's player.bond_keepsakes (batch 3).
	var alpha_keeps:Dictionary={}
	var KIND_L:="keepsake_lingpopo"
	var KIND_M:="keepsake_milu"
	var kit_l:=Goals.keepsake_item(KIND_L)
	var kit_m:=Goals.keepsake_item(KIND_M)
	var memorial:=Goals.FESTIVAL_BELL_REWARD
	var kit_memorial:=Goals.keepsake_item(memorial)
	expect(Goals.keepsake_kind("lingpopo",3)==KIND_L and Goals.keepsake_kind("milu",3)==KIND_M and kit_l=="keepsake_lingpopo_kit" and kit_m=="keepsake_milu_kit","lingpopo 3 and milu 3 carry the keepsakes keepsake_lingpopo / keepsake_milu")
	expect(Goals.keepsake_kind("lingpopo",2).is_empty() and Goals.keepsake_kind("lingpopo",4)==memorial,"Only the final festival event carries the memorial keepsake")

	# 1. Fresh, private views.
	for c:Client in [alpha,beta]:
		var other:Client=beta if c==alpha else alpha
		var keys:Array=c.goals().keys()
		keys.sort()
		var want:Array=Bond.RESIDENTS.duplicate()
		want.sort()
		expect(keys==want,"%s's resident_goals lists exactly the twelve residents (%s)"%[c.label,str(keys)])
		private_check(c,[other],"case 1")
	expect_view(alpha,ALPHA_BONDS,null,"case 1 fresh")
	expect_view(beta,BETA_BONDS,null,"case 1 fresh")
	var lp:Dictionary=alpha.goals().get("lingpopo",{})
	var festival_row:={"id":"festival_done","label":str(Goals.NEEDS.festival_done),"met":false}
	expect(str(Goals.NEEDS.festival_done)=="島上完成過一次風鈴接力","festival_done label text")
	expect(text(lp)==text({"1":{"state":"open","choice":"","needs":[{"id":"bell_inspected","label":"查看風鈴樹與裂開的小鈴","met":false}]},"2":{"state":"open","choice":""},"3":{"state":"open","choice":"","keepsake":keep_row(KIND_L,false)},"4":{"state":"open","choice":"","needs":[festival_row],"keepsake":keep_row(memorial,false)}}),"alpha's four lingpopo events are open; 3 carries its keepsake claimed=false; 4 carries needs festival_done met=false (%s)"%text(lp))
	expect(goal_row(beta,"lingpopo","4")==text({"state":"locked","choice":"","needs":[festival_row],"keepsake":keep_row(memorial,false)}),"beta's lingpopo 4 is locked and carries its own needs row met=false (%s)"%goal_row(beta,"lingpopo","4"))
	var fresh_festival:Dictionary=server.world.state.get("festival",{})
	expect(int(fresh_festival.get("round",-1))==0 and fresh_festival.get("active",true)==false,"server festival record: no round played yet (%s)"%text(fresh_festival))
	var mi:Dictionary=beta.goals().get("milu",{})
	expect(text(mi)==text({"1":{"state":"locked","choice":""},"2":{"state":"locked","choice":"","needs":[{"id":"recipe_pages","label":"找齊三片食譜紙角","met":false}]},"3":{"state":"locked","choice":"","keepsake":keep_row(KIND_M,false)},"4":{"state":"locked","choice":"","needs":[{"id":"shared_meal","label":"親手上一輪共享料理","met":false}]}}),"beta's milu goals are locked; milu 3 carries its keepsake claimed=false (%s)"%text(mi))
	expect(goal_row(alpha,"milu","3")==text({"state":"open","choice":"","keepsake":keep_row(KIND_M,false)}),"alpha's milu 3 is open (preset milu 14) and unclaimed (%s)"%goal_row(alpha,"milu","3"))
	expect(server_keeps(ALPHA)=="null" and server_keeps(BETA)=="null","server: nobody has a bond_keepsakes key yet")
	expect(canon(alpha.bag())==canon(ALPHA_BAG) and canon(beta.bag())==canon(BETA_BAG),"preset bags arrive unchanged in the own snapshots")
	expect(server_goals(ALPHA)=="null" and server_goals(BETA)=="null","server: nobody has a bond_goals key yet")

	# 2. Fixed-order steps goal (lingpopo 2, order 102): wrong orders refused, retry accepted.
	await refuse(alpha,Goals.ACTION,BELL,"lingpopo:2::012",order_msg("lingpopo"),"case 2 alpha lingpopo 2 order 012",[beta])
	await refuse(alpha,Goals.ACTION,BELL,"lingpopo:2::201",order_msg("lingpopo"),"case 2 alpha lingpopo 2 order 201",[beta])
	await refuse(alpha,Goals.ACTION,BELL,"lingpopo:2::11","三個步驟都要做過一次。","case 2 alpha lingpopo 2 with two steps",[beta])
	var bag_a:=canon(alpha.bag())
	var bag_b:=canon(beta.bag())
	var r:=await act(alpha,Goals.ACTION,BELL,"lingpopo:2::102")
	expect(r.ok and r.message==success_msg("lingpopo",2),"case 2 alpha completes lingpopo 2 in the drawn order (%s)"%r.message)
	await settle([alpha,beta])
	alpha_record={"lingpopo":{"2":""}}
	expect_view(alpha,ALPHA_BONDS,alpha_record,"case 2 alpha after lingpopo 2")
	expect(server_goals(ALPHA)==text(alpha_record),"case 2 server holds alpha's lingpopo 2 (%s)"%server_goals(ALPHA))
	expect(canon(alpha.bag())==bag_a,"case 2 the steps goal costs nothing")
	expect_view(beta,BETA_BONDS,null,"case 2 beta unaffected by alpha's goal")
	expect(canon(beta.bag())==bag_b and server_goals(BETA)=="null","case 2 beta's bag and server record unaffected")
	private_check(beta,[alpha],"case 2 beta")
	private_check(alpha,[beta],"case 2 alpha")

	# 3. Deliver goal (lingpopo 3 with soup): exact charge, both ends consistent.
	bag_a=canon(alpha.bag())
	r=await act(alpha,Goals.ACTION,BELL,"lingpopo:3:soup:")
	expect(r.ok and r.message==success_msg("lingpopo",3),"case 3 alpha delivers lingpopo 3 with soup (%s)"%r.message)
	await settle([alpha,beta])
	var paid:Dictionary=Goals.cost(Goals.goal("lingpopo",3),"soup")
	expect(text(paid)==text({"copper_ingot":4,"glass":2,"soup":1}),"lingpopo 3 soup costs copper_ingot 4, glass 2, soup 1")
	# Batch 3: lingpopo 3 is a keepsake goal — exactly the cost leaves and exactly one kit arrives.
	expect(canon(alpha.bag())==plus(plus(bag_a,paid,-1),{kit_l:1}),"case 3 exactly the cost left alpha's bag and exactly one %s arrived (%s)"%[kit_l,text(canon(alpha.bag()))])
	expect(int(canon(alpha.bag()).get(kit_l,0))==1,"case 3 alpha holds exactly 1 %s"%kit_l)
	alpha_record={"lingpopo":{"2":"","3":"soup"}}
	alpha_keeps={KIND_L:true}
	expect_view(alpha,ALPHA_BONDS,alpha_record,"case 3 alpha after lingpopo 3",alpha_keeps)
	var row:Dictionary=alpha.goals().get("lingpopo",{}).get("3",{})
	expect(str(row.get("state",""))=="done" and str(row.get("choice",""))=="soup","case 3 alpha's own snapshot shows lingpopo 3 done with soup")
	expect(text(row.get("keepsake",{}))==text(keep_row(KIND_L,true)),"case 3 alpha's own lingpopo 3 keepsake claimed=true (%s)"%text(row.get("keepsake",{})))
	expect(server_goals(ALPHA)==text(alpha_record),"case 3 server holds alpha's record %s (got %s)"%[text(alpha_record),server_goals(ALPHA)])
	expect(server_keeps(ALPHA)==text(alpha_keeps),"case 3 server holds alpha's bond_keepsakes %s (got %s)"%[text(alpha_keeps),server_keeps(ALPHA)])
	expect_view(beta,BETA_BONDS,null,"case 3 beta's own lingpopo goals still open")
	expect(goal_row(beta,"lingpopo","3")==text({"state":"open","choice":"","keepsake":keep_row(KIND_L,false)}),"case 3 beta's own lingpopo 3 still open with keepsake claimed=false (%s)"%goal_row(beta,"lingpopo","3"))
	expect(canon(beta.bag())==bag_b and server_keeps(BETA)=="null","case 3 beta's bag unchanged and beta has no bond_keepsakes on the server")
	private_check(beta,[alpha],"case 3 beta")
	private_check(alpha,[beta],"case 3 alpha")

	# 4. Resend of the same sequence number (raw request_action RPC) is dropped.
	expect(alpha.session.counter==int(r.sequence),"alpha's last used sequence is the lingpopo 3 delivery")
	bag_a=canon(alpha.bag())
	var view_a:=text(alpha.goals())
	var marks:=[alpha.notices.size(),beta.notices.size()]
	alpha.session.request_action.rpc_id(1,int(r.sequence),Goals.ACTION,BELL,"lingpopo:3:soup:",alpha.region(),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==marks[0] and beta.notices.size()==marks[1],"re-sent delivery (same sequence) gets no notice")
	expect(canon(alpha.bag())==bag_a and int(bag_a.get("soup",0))==1 and text(alpha.goals())==view_a,"re-sent delivery charges nothing more (soup still 1) and changes no view")
	expect(int(canon(alpha.bag()).get(kit_l,0))==1,"re-sent delivery grants no second keepsake (still exactly 1 %s)"%kit_l)
	expect(server_goals(ALPHA)==text(alpha_record) and server_keeps(ALPHA)==text(alpha_keeps),"re-sent delivery leaves the server records as they were")

	# 5. Refusals, both ends unchanged.
	await refuse(alpha,Goals.ACTION,BELL,"lingpopo:3:soup:",done_msg("lingpopo",3),"case 5 alpha repeats lingpopo 3",[beta])
	await refuse(alpha,Goals.ACTION,BELL,"lingpopo:3:salad:",done_msg("lingpopo",3),"case 5 alpha repeats lingpopo 3 with another dish",[beta])
	await refuse(alpha,Goals.ACTION,BELL,"lingpopo:2::102",done_msg("lingpopo",2),"case 5 alpha repeats lingpopo 2",[beta])
	expect(beta.pos().distance_to(Vector2(BELL)+HALF)>3.2,"beta stands out of reach of lingpopo (%s)"%str(beta.pos()))
	await refuse(beta,Goals.ACTION,BELL,"lingpopo:2::102",MSG_FAR,"case 5 beta tries lingpopo 2 from milu's side",[alpha])
	await refuse(beta,Goals.ACTION,MILU,"milu:1::",stage_msg("milu",1),"case 5 beta tries milu 1 before meeting milu",[alpha])
	expect_view(alpha,ALPHA_BONDS,alpha_record,"case 5 alpha after all refusals",alpha_keeps)
	expect_view(beta,BETA_BONDS,null,"case 5 beta after all refusals")

	# 5b. Batch-2 prerequisite (needs festival_done) on alpha's lingpopo 4.
	var need_text:=str(Goals.NEEDS.festival_done)
	expect(int(server.world.state.festival.round)==0,"case 5b no festival round yet on the server")
	expect(goal_row(alpha,"lingpopo","4")==text({"state":"open","choice":"","needs":[{"id":"festival_done","label":need_text,"met":false}],"keepsake":keep_row(memorial,false)}),"case 5b alpha's own snapshot: lingpopo 4 open, needs festival_done met=false (%s)"%goal_row(alpha,"lingpopo","4"))
	await refuse(alpha,Goals.ACTION,BELL,"lingpopo:4::","還不能一起做這件事：要先「%s」。"%need_text,"case 5b alpha tries lingpopo 4 before any festival round",[beta])
	expect(server_goals(ALPHA)==text(alpha_record),"case 5b the refused prerequisite goal wrote nothing on the server")
	expect_view(alpha,ALPHA_BONDS,alpha_record,"case 5b alpha after the prerequisite refusal",alpha_keeps)
	expect_view(beta,BETA_BONDS,null,"case 5b beta after alpha's prerequisite refusal")
	# DIRECT WRITE 2 (disclosed in the header): one finished festival round.
	var now:=float(server.world.state.time)
	server.world.state["festival"]={"round":1,"active":false,"collected":12,"contributors":{BETA:12},"started":now-120.0,"finished":now-60.0,"ready":now+240.0,"best":60.0}
	var met_seen:=await wait_until(func():
		var rows:=needs_rows(alpha,"lingpopo","4")
		return rows.size()==1 and rows[0] is Dictionary and rows[0].get("met",false)==true,3.0)
	expect(met_seen,"case 5b alpha's next snapshot shows festival_done met=true (%s)"%goal_row(alpha,"lingpopo","4"))
	await settle([alpha,beta])
	var met_row:={"id":"festival_done","label":need_text,"met":true}
	expect(goal_row(alpha,"lingpopo","4")==text({"state":"open","choice":"","needs":[met_row],"keepsake":keep_row(memorial,false)}),"case 5b alpha's lingpopo 4 still open, needs met=true")
	expect(goal_row(beta,"lingpopo","4")==text({"state":"locked","choice":"","needs":[met_row],"keepsake":keep_row(memorial,false)}),"case 5b beta's own lingpopo 4: locked (beta is 信任) with met=true (festival_done is island-wide) (%s)"%goal_row(beta,"lingpopo","4"))
	expect_view(alpha,ALPHA_BONDS,alpha_record,"case 5b alpha after the festival round",alpha_keeps)
	expect_view(beta,BETA_BONDS,null,"case 5b beta after the festival round")
	bag_a=canon(alpha.bag())
	bag_b=canon(beta.bag())
	r=await act(alpha,Goals.ACTION,BELL,"lingpopo:4::")
	expect(r.ok and r.message==success_msg("lingpopo",4),"case 5b alpha completes lingpopo 4 once the festival round exists (%s)"%r.message)
	await settle([alpha,beta])
	alpha_record={"lingpopo":{"2":"","3":"soup","4":""}}
	alpha_keeps[memorial]=true
	expect_view(alpha,ALPHA_BONDS,alpha_record,"case 5b alpha after lingpopo 4",alpha_keeps)
	expect(goal_row(alpha,"lingpopo","4")==text({"state":"done","choice":"","keepsake":keep_row(memorial,true)}),"case 5b alpha's lingpopo 4 done and carries no needs row (%s)"%goal_row(alpha,"lingpopo","4"))
	expect(server_goals(ALPHA)==text(alpha_record),"case 5b server holds alpha's record %s (got %s)"%[text(alpha_record),server_goals(ALPHA)])
	expect(canon(alpha.bag())==plus(bag_a,{kit_memorial:1}),"case 5b only adds the memorial bell")
	bag_a=canon(alpha.bag())
	expect(canon(beta.bag())==bag_b and server_goals(BETA)=="null","case 5b beta's bag and server record unaffected")
	expect_view(beta,BETA_BONDS,null,"case 5b beta unaffected by alpha's lingpopo 4")
	expect(goal_row(beta,"lingpopo","4")==text({"state":"locked","choice":"","needs":[met_row],"keepsake":keep_row(memorial,false)}),"case 5b beta's lingpopo 4 reflects beta's own state (locked, own needs row)")
	var beta_dump:=JSON.stringify(beta.session.snapshot)
	expect(beta_dump.count("\"festival_done\"")==1,"case 5b beta's whole snapshot holds exactly one festival_done needs row (its own; alpha's rows never arrive)")
	expect(JSON.stringify(alpha.session.snapshot).count("\"festival_done\"")==0,"case 5b alpha's snapshot holds no festival_done row once done")
	private_check(beta,[alpha],"case 5b beta")
	private_check(alpha,[beta],"case 5b alpha")
	# Duplicate sequence number of the lingpopo 4 completion applies once.
	expect(alpha.session.counter==int(r.sequence),"alpha's last used sequence is the lingpopo 4 completion")
	view_a=text(alpha.goals())
	var view_b:=text(beta.goals())
	marks=[alpha.notices.size(),beta.notices.size()]
	alpha.session.request_action.rpc_id(1,int(r.sequence),Goals.ACTION,BELL,"lingpopo:4::",alpha.region(),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==marks[0] and beta.notices.size()==marks[1],"case 5b re-sent lingpopo 4 (same sequence) gets no notice")
	expect(text(alpha.goals())==view_a and text(beta.goals())==view_b and canon(alpha.bag())==bag_a and canon(beta.bag())==bag_b,"case 5b re-sent lingpopo 4 changes no view and no bag")
	expect(server_goals(ALPHA)==text(alpha_record),"case 5b re-sent lingpopo 4 leaves the server record as it was")
	await refuse(alpha,Goals.ACTION,BELL,"lingpopo:4::",done_msg("lingpopo",4),"case 5b alpha repeats lingpopo 4",[beta])

	# 5c. Batch 3: alpha places the lingpopo keepsake at home with the normal build
	# action (World.BUILD[keepsake_lingpopo] costs exactly one kit). Real action.
	var build_key:=World.key(build_cell)
	expect(World.BUILD.has(KIND_L) and int(World.BUILD[KIND_L].get(kit_l,0))==1,"World.BUILD[%s] costs exactly one %s"%[KIND_L,kit_l])
	expect(seen_object(alpha,build_cell).is_empty() and seen_object(beta,build_cell).is_empty() and not server.world.state.objects.has(build_key),"case 5c build cell %s is empty on the server and in both snapshots"%build_key)
	expect(alpha.pos().distance_to(Vector2(build_cell)+HALF)<=3.2,"case 5c the build cell is within reach of alpha (%s)"%str(alpha.pos()))
	bag_a=canon(alpha.bag())
	bag_b=canon(beta.bag())
	view_b=text(beta.goals())
	r=await act(alpha,"build",build_cell,KIND_L)
	expect(r.ok and r.message=="放好了%s，家園又多了一點你的心意"%str(World.BUILD[KIND_L].name),"case 5c alpha places the lingpopo keepsake with the build action (%s)"%r.message)
	await settle([alpha,beta])
	expect(canon(alpha.bag())==plus(bag_a,{kit_l:1},-1) and not canon(alpha.bag()).has(kit_l),"case 5c exactly the one kit left alpha's bag (%s)"%text(canon(alpha.bag())))
	var live_obj:Dictionary=server.world.state.objects.get(build_key,{})
	expect(str(live_obj.get("type",""))==KIND_L and str(live_obj.get("owner",""))==ALPHA,"case 5c server object at %s is %s owned by alpha"%[build_key,KIND_L])
	var placed_b:=seen_object(beta,build_cell)
	expect(str(placed_b.get("type",""))==KIND_L and str(placed_b.get("owner",""))==alpha.session.own_id,"case 5c beta's public snapshot shows %s at %s with owner = alpha's public id (%s)"%[KIND_L,build_key,text(placed_b)])
	var placed_a:=seen_object(alpha,build_cell)
	expect(str(placed_a.get("type",""))==KIND_L and str(placed_a.get("owner",""))==alpha.session.own_id,"case 5c alpha's own snapshot shows the same placed keepsake")
	expect(Vector2i(World.bond_place(server.world.state,"lingpopo")[1])==bell_cell,"case 5c lingpopo's cell did not move because of the placed keepsake")
	expect_view(alpha,ALPHA_BONDS,alpha_record,"case 5c placing does not un-claim the keepsake",alpha_keeps)
	expect(server_keeps(ALPHA)==text(alpha_keeps),"case 5c server bond_keepsakes unchanged by placing")
	expect(canon(beta.bag())==bag_b and text(beta.goals())==view_b,"case 5c beta's bag and own view unaffected")
	private_check(beta,[alpha],"case 5c beta")

	# 5d. Batch 3 claim (resident_keepsake) refusals that need no preset.
	await refuse(beta,Goals.CLAIM_ACTION,MILU,"milu:3",not_done_msg("milu",3),"case 5d beta claims milu 3 it never did",[alpha])
	await refuse(alpha,Goals.CLAIM_ACTION,BELL,"lingpopo:3",claimed_msg(KIND_L),"case 5d alpha claims lingpopo 3 again (already granted on completion)",[beta])
	await refuse(alpha,Goals.CLAIM_ACTION,BELL,"lingpopo:2",MSG_NO_KEEPSAKE,"case 5d alpha claims lingpopo 2 (no keepsake)",[beta])
	# DIRECT WRITE 3 (disclosed "old save" preset): alpha's live server record gets a
	# milu 3 done entry and NO bond_keepsakes entry for keepsake_milu, as if milu 3
	# had been completed before batch 3. Nothing is charged for it.
	var live_alpha:Dictionary=server.world.state.players[ALPHA]
	expect(not Goals.done(live_alpha,"milu").has(3) and not Goals.keepsake_claimed(live_alpha,KIND_M),"case 5d before the preset alpha has no milu 3 record and no milu keepsake")
	var live_goals:Dictionary=live_alpha[Goals.RECORD_KEY]
	live_goals["milu"]={"3":"soup"}
	alpha_record={"lingpopo":{"2":"","3":"soup","4":""},"milu":{"3":"soup"}}
	var old_seen:=await wait_until(func():return goal_row(alpha,"milu","3")==text({"state":"done","choice":"soup","keepsake":keep_row(KIND_M,false)}),3.0)
	await settle([alpha,beta])
	expect(old_seen,"case 5d alpha's own summary: preset milu 3 done, keepsake claimed=false (%s)"%goal_row(alpha,"milu","3"))
	expect_view(alpha,ALPHA_BONDS,alpha_record,"case 5d alpha after the old-save preset",alpha_keeps)
	expect(server_goals(ALPHA)==text(alpha_record) and server_keeps(ALPHA)==text(alpha_keeps),"case 5d server: milu 3 done, bond_keepsakes still only Lingpopo’s two keepsakes")
	expect(goal_row(beta,"milu","3")==text({"state":"locked","choice":"","keepsake":keep_row(KIND_M,false)}),"case 5d beta's own milu 3 is locked and unclaimed (%s)"%goal_row(beta,"milu","3"))
	# Away from milu: the generic reach gate refuses; nothing changes on either end.
	expect(alpha.pos().distance_to(Vector2(MILU)+HALF)>3.2,"case 5d alpha stands out of reach of milu (%s)"%str(alpha.pos()))
	await refuse(alpha,Goals.CLAIM_ACTION,MILU,"milu:3",MSG_FAR,"case 5d alpha claims milu 3 from lingpopo's side",[beta])
	expect(not canon(alpha.bag()).has(kit_m),"case 5d the far claim granted no %s"%kit_m)
	# DIRECT WRITE 4 (disclosed): alpha's live server position next to milu.
	var moved:bool=await teleport(alpha,alpha_milu_stand,"case 5d DIRECT WRITE 4")
	if not moved:return false
	bag_a=canon(alpha.bag())
	bag_b=canon(beta.bag())
	view_b=text(beta.goals())
	r=await act(alpha,Goals.CLAIM_ACTION,MILU,"milu:3")
	expect(r.ok and r.message==claim_msg("milu",KIND_M),"case 5d alpha claims the milu keepsake next to milu (%s)"%r.message)
	await settle([alpha,beta])
	expect(canon(alpha.bag())==plus(bag_a,{kit_m:1}) and int(canon(alpha.bag()).get(kit_m,0))==1,"case 5d exactly one %s arrived and nothing else changed (%s)"%[kit_m,text(canon(alpha.bag()))])
	alpha_keeps[KIND_M]=true
	expect(goal_row(alpha,"milu","3")==text({"state":"done","choice":"soup","keepsake":keep_row(KIND_M,true)}),"case 5d alpha's own milu 3 keepsake claimed=true (%s)"%goal_row(alpha,"milu","3"))
	expect_view(alpha,ALPHA_BONDS,alpha_record,"case 5d alpha after the claim",alpha_keeps)
	expect(server_goals(ALPHA)==text(alpha_record) and server_keeps(ALPHA)==text(alpha_keeps),"case 5d server holds alpha's bond_keepsakes %s (got %s)"%[text(alpha_keeps),server_keeps(ALPHA)])
	expect(canon(beta.bag())==bag_b and text(beta.goals())==view_b and server_keeps(BETA)=="null","case 5d beta's bag, own view and server record unaffected by alpha's claim")
	private_check(beta,[alpha],"case 5d beta after alpha's claim")
	private_check(alpha,[beta],"case 5d alpha after the claim")
	# Same-sequence resend of the claim applies once.
	expect(alpha.session.counter==int(r.sequence),"alpha's last used sequence is the milu keepsake claim")
	bag_a=canon(alpha.bag())
	view_a=text(alpha.goals())
	view_b=text(beta.goals())
	marks=[alpha.notices.size(),beta.notices.size()]
	alpha.session.request_action.rpc_id(1,int(r.sequence),Goals.CLAIM_ACTION,MILU,"milu:3",alpha.region(),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==marks[0] and beta.notices.size()==marks[1],"case 5d re-sent claim (same sequence) gets no notice")
	expect(canon(alpha.bag())==bag_a and int(canon(alpha.bag()).get(kit_m,0))==1 and text(alpha.goals())==view_a and text(beta.goals())==view_b,"case 5d re-sent claim grants nothing more (still exactly 1 %s) and changes no view"%kit_m)
	expect(server_keeps(ALPHA)==text(alpha_keeps),"case 5d re-sent claim leaves the server bond_keepsakes as it was")
	# A fresh (new sequence) second claim is refused.
	await refuse(alpha,Goals.CLAIM_ACTION,MILU,"milu:3",claimed_msg(KIND_M),"case 5d alpha claims milu 3 a second time",[beta])
	# DIRECT WRITE 5 (disclosed): alpha back to its lingpopo stand for the later cases.
	moved=await teleport(alpha,alpha_stand,"case 5d DIRECT WRITE 5")
	if not moved:return false
	await settle([alpha,beta])

	# 6. Alpha disconnects and rejoins.
	view_a=text(alpha.goals())
	bag_a=canon(alpha.bag())
	await leave(alpha)
	expect(await wait_until(func():return int(beta.session.snapshot.get("room_population",0))==1,4.0),"server sees alpha leave (room population 1)")
	alpha=await join("alpha",ALPHA,port)
	expect(joined(alpha),"alpha rejoins with the same token")
	if not joined(alpha):return false
	await settle([alpha,beta])
	expect(text(alpha.goals())==view_a,"alpha's whole resident_goals is intact after rejoin")
	expect(canon(alpha.bag())==bag_a,"alpha's bag intact after rejoin")
	expect_view(alpha,ALPHA_BONDS,alpha_record,"case 6 alpha after rejoin (lingpopo 2, 3, 4 and preset milu 3 done; all three keepsakes claimed)",alpha_keeps)
	private_check(alpha,[beta],"case 6 alpha after rejoin")
	private_check(beta,[alpha],"case 6 beta after alpha's rejoin")

	# 7. Normal shutdown: the save on disk, field by field.
	await settle([alpha,beta])
	var final_views:={ALPHA:text(alpha.goals()),BETA:text(beta.goals())}
	var final_bags:={ALPHA:canon(alpha.bag()),BETA:canon(beta.bag())}
	# Alpha: lingpopo 3 cost paid, lingpopo kit granted then placed, milu kit claimed.
	expect(final_bags[ALPHA]==canon({"copper_ingot":1,"glass":1,"soup":1,"radish":1,kit_m:1,kit_memorial:1}) and final_bags[BETA]==canon(BETA_BAG),"final bags: alpha %s, beta %s"%[text(final_bags[ALPHA]),text(final_bags[BETA])])
	await leave(alpha)
	await leave(beta)
	expect(await stop_server(),"server Session shuts down with a final save")
	var disk=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	expect(disk is Dictionary,"save file parses")
	if not disk is Dictionary:return false
	expect(Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"saved world passes SaveSchema")
	var disk_a=disk.players.get(ALPHA,{})
	var disk_b=disk.players.get(BETA,{})
	expect(disk_a is Dictionary and text(disk_a.get(Goals.RECORD_KEY,null))==text(alpha_record),"save holds alpha's exact bond_goals %s (got %s)"%[text(alpha_record),text(disk_a.get(Goals.RECORD_KEY,null)) if disk_a is Dictionary else "?"])
	expect(disk_b is Dictionary and not disk_b.has(Goals.RECORD_KEY),"save writes no bond_goals key for beta")
	expect(disk_a is Dictionary and text(disk_a.get(Goals.KEEPSAKE_KEY,null))==text(alpha_keeps),"save holds alpha's exact bond_keepsakes %s (got %s)"%[text(alpha_keeps),text(disk_a.get(Goals.KEEPSAKE_KEY,null)) if disk_a is Dictionary else "?"])
	expect(disk_b is Dictionary and not disk_b.has(Goals.KEEPSAKE_KEY),"save writes no bond_keepsakes key for beta")
	var disk_objects=disk.get("objects",{})
	var disk_obj=disk_objects.get(World.key(build_cell),null) if disk_objects is Dictionary else null
	expect(disk_obj is Dictionary and str(disk_obj.get("type",""))==KIND_L and str(disk_obj.get("owner",""))==ALPHA,"save holds the placed %s at %s owned by alpha (%s)"%[KIND_L,World.key(build_cell),text(disk_obj)])
	var disk_milu=disk_a.get("bonds",{}).get("milu",{}) if disk_a is Dictionary else {}
	expect(disk_milu is Dictionary and int(disk_milu.get("points",-1))==14,"save keeps alpha's preset milu bond at 14 points (claim adds no points)")
	for token in [ALPHA,BETA]:
		var person=disk.players.get(token,{})
		expect(canon(person.get("inventory",{}))==final_bags[token],"save holds %s's exact bag"%token)
		var lb=person.get("bonds",{}).get("lingpopo",{})
		var want_points:int=int((ALPHA_BONDS if token==ALPHA else BETA_BONDS).lingpopo.points)
		expect(lb is Dictionary and int(lb.get("points",-1))==want_points and int(lb.get("talk_day",0))==-1 and int(lb.get("gift_day",0))==-1,"save keeps %s's lingpopo bond at %d points (goals add no points)"%[token,want_points])
	var disk_festival=disk.get("festival",{})
	expect(disk_festival is Dictionary and int(disk_festival.get("round",-1))==1 and disk_festival.get("active",true)==false,"save holds the one finished festival round (%s)"%text(disk_festival))

	# 8. Restart: alpha, beta and a late joiner.
	var port2:=start_server()
	expect(port2>0,"a new server Session hosts the same save")
	if port2==0:return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	expect(joined(alpha) and joined(beta),"both clients rejoin the restarted server")
	if not joined(alpha) or not joined(beta):return false
	await settle([alpha,beta])
	expect(text(alpha.goals())==final_views[ALPHA],"alpha's whole resident_goals identical after restart")
	expect(text(beta.goals())==final_views[BETA],"beta's whole resident_goals identical after restart")
	expect(canon(alpha.bag())==final_bags[ALPHA] and canon(beta.bag())==final_bags[BETA],"both bags identical after restart")
	expect(server_goals(ALPHA)==text(alpha_record) and server_goals(BETA)=="null","restarted server holds alpha's record and none for beta")
	await refuse(alpha,Goals.ACTION,BELL,"lingpopo:2::102",done_msg("lingpopo",2),"case 8 alpha's lingpopo 2 is still done after restart",[beta])
	await refuse(alpha,Goals.ACTION,BELL,"lingpopo:4::",done_msg("lingpopo",4),"case 8 alpha's prerequisite goal lingpopo 4 is still done after restart",[beta])
	expect(goal_row(alpha,"lingpopo","4")==text({"state":"done","choice":"","keepsake":keep_row(memorial,true)}),"case 8 alpha's lingpopo 4 done after restart (%s)"%goal_row(alpha,"lingpopo","4"))
	expect(goal_row(beta,"lingpopo","4")==text({"state":"locked","choice":"","needs":[{"id":"festival_done","label":str(Goals.NEEDS.festival_done),"met":true}],"keepsake":keep_row(memorial,false)}),"case 8 beta's lingpopo 4 still locked with met=true after restart (festival round saved)")
	expect_view(alpha,ALPHA_BONDS,alpha_record,"case 8 alpha after restart",alpha_keeps)
	expect_view(beta,BETA_BONDS,null,"case 8 beta after restart")
	# Batch 3 after restart: kits, claimed flags (from bond_keepsakes) and the placed object.
	expect(server_keeps(ALPHA)==text(alpha_keeps) and server_keeps(BETA)=="null","case 8 restarted server holds alpha's bond_keepsakes %s and none for beta"%server_keeps(ALPHA))
	expect(int(canon(alpha.bag()).get(kit_m,0))==1 and not canon(alpha.bag()).has(kit_l),"case 8 alpha still holds exactly 1 %s and no %s (placed)"%[kit_m,kit_l])
	expect(goal_row(alpha,"lingpopo","3")==text({"state":"done","choice":"soup","keepsake":keep_row(KIND_L,true)}) and goal_row(alpha,"milu","3")==text({"state":"done","choice":"soup","keepsake":keep_row(KIND_M,true)}),"case 8 alpha's lingpopo 3 and milu 3 keepsakes still claimed=true after restart")
	expect(goal_row(beta,"lingpopo","3")==text({"state":"open","choice":"","keepsake":keep_row(KIND_L,false)}),"case 8 beta's own lingpopo 3 still unclaimed after restart")
	var placed_after:=seen_object(beta,build_cell)
	expect(str(placed_after.get("type",""))==KIND_L and str(placed_after.get("owner",""))==alpha.session.own_id,"case 8 beta still sees alpha's placed %s at %s after restart (%s)"%[KIND_L,World.key(build_cell),text(placed_after)])
	await refuse(alpha,Goals.CLAIM_ACTION,BELL,"lingpopo:3",claimed_msg(KIND_L),"case 8 alpha cannot claim lingpopo 3 again after restart",[beta])
	gamma=await join("gamma",GAMMA,port2)
	expect(joined(gamma),"late joiner gamma joins with a fresh token")
	if not joined(gamma):return false
	await settle([alpha,beta,gamma])
	expect_view(gamma,{},null,"case 8 late joiner (no bonds: everything locked)")
	var nothing_done:=true
	var all_locked:=true
	var gv:Dictionary=gamma.goals()
	for resident in gv:
		var stages=gv[resident]
		if not stages is Dictionary:
			all_locked=false
			continue
		for key in stages:
			var entry=stages[key]
			if not entry is Dictionary or str(entry.get("state",""))!="locked":all_locked=false
			if entry is Dictionary and str(entry.get("state",""))=="done":nothing_done=false
	expect(gv.size()==Bond.RESIDENTS.size() and all_locked and nothing_done,"case 8 late joiner sees all twelve residents, every goal locked, nothing done")
	private_check(gamma,[alpha,beta],"case 8 gamma")
	private_check(alpha,[beta,gamma],"case 8 alpha")
	private_check(beta,[alpha,gamma],"case 8 beta")
	expect(text(alpha.goals())==final_views[ALPHA] and text(beta.goals())==final_views[BETA],"gamma's arrival changes neither alpha's nor beta's view")
	await teleport(alpha,alpha_milu_stand,"Apron wearer visits Milu")
	await teleport(beta,alpha_milu_stand,"Apron guest visits Milu")
	# Transport fixture: the earned quest and save path are covered by the core suite.
	var wearer:Dictionary=server.world.state.players[ALPHA]
	wearer.bonds.milu.points=24
	wearer.bond_goals.milu["4"]=""
	await refuse(beta,Goals.APRON_ACTION,MILU,"","完成米露的共餐事件後可穿戴。","Guest cannot equip the apron",[alpha])
	var equipped:=await act(alpha,Goals.APRON_ACTION,MILU,"")
	expect(equipped.replied and equipped.ok,"Alpha equips the apron over WebSocket")
	var visible:=await wait_until(func():
		return bool(beta.session.snapshot.get("players",{}).get(alpha.session.own_id,{}).get(Goals.APRON_KEY,false)),3.0)
	expect(visible and not beta.me().get(Goals.APRON_KEY,false),"Beta sees Alpha's apron without equipping one")
	await leave(gamma)
	gamma=null
	await leave(alpha)
	await leave(beta)
	expect(await stop_server(),"restarted server shuts down cleanly")
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
