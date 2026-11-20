extends SceneTree
## T067 玻璃爐 (glass_furnace) two-client Session acceptance: hoist-gated build,
## owner-only queue/claim (others refused), snapshot sync, adjacent-chest supply,
## disconnect/rejoin, normal shutdown + restart, late joiner.
##
## LEVEL: one machine, ONE Godot process. Inside the single SceneTree a real
## dedicated server Session listens on a free 127.0.0.1 port with the WebSocket
## transport (WebSocketMultiplayerPeer) and separate client Session nodes join it
## over loopback. Every Session lives in its own branch with its own
## SceneMultiplayer, so requests, notices and snapshots really travel through the
## RPC + WebSocket path. Clients only read their own received snapshots; the
## server World is never touched after seeding except for reading the on-disk
## save file after the normal shutdown.
##
## SEEDED FIXTURE (disclosed, written to a fresh TEMP folder and validated with
## SaveSchema before use): picnic=true; mine_depths={unlocked:6, ready:{},
## pumped:24, hoist:false} (B6 opened, hoist NOT repaired); fixed positions at
## home beside the furnace cell (38,34): alpha (37.5,34.5), beta (39.5,35.5);
## exact bags: alpha {stone 25, iron_ingot 6, crystal_sand 3,
## wood 22, vein_quartz 2} (furnace cost + one glass job + one crystal sand job +
## a chest (wood 20) + 1 wood to stock it), beta {stone 25, iron_ingot 6,
##, crystal_sand 3, wood 1} (so beta's refusals are never about
## materials); a third seeded islander "mender" stands on the jinguashi surface
## beside the hoist sign holding exactly Mines.HOIST_COST.
## Everything after the seed goes through client Sessions over the network: the
## refused builds, the REAL `mine_hoist_repair` by mender, the furnace build, the
## chest build, deposits, prepare_material_box, sourced and plain queues, claims,
## disconnects. Nothing is walked (positions are seeded within reach).
## Clock: world time passes only on the live server; to shorten the 120 s / 60 s
## furnace jobs the test temporarily sets Engine.time_scale (TIME_SCALE) inside
## this one process and restores 1.0 before acting; real-time waits/timers ignore
## the time scale.
## NOT covered: multiple processes, cross-machine, TLS/wss, latency/packet loss
## injection, crash durability (only a normal shutdown with a final save).
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Mines=preload("res://scripts/mine_depths.gd")
const Regions=preload("res://scripts/regions.gd")
const Sources=preload("res://scripts/material_sources.gd")
const Supply=preload("res://scripts/material_supply.gd")
const KEY:="glass-furnace-session"
const ALPHA:="furnace-session-alpha-token"
const BETA:="furnace-session-beta-token"
const GAMMA:="furnace-session-gamma-token"
const MENDER:="furnace-session-mender-token"
const SURFACE:="jinguashi"
const SURFACE_ARRIVAL:=Vector2(27.5,19.5)
const FURNACE:=Vector2i(38,34)
const CHEST:=Vector2i(38,36)
const STAND_A:=Vector2(37.5,34.5)
const STAND_B:=Vector2(40.5,35.5)
const FURNACE_COST:={"stone":25,"iron_ingot":6}
const CHEST_COST:={"wood":20}
const GLASS_COST:={"crystal_sand":3,"wood":1}
const SAND_COST:={"vein_quartz":2}
const TIME_SCALE:=20.0
## Owner-only refusal: World.process_industry literal, identical to MaterialSources.MSG_PROCESSOR.
const OWNER_ONLY_MSG:=Sources.MSG_PROCESSOR
const NOT_DONE_PREFIX:="加工尚未完成"
const EMPTY_SHELF_MSG:="目前沒有完成的加工"
const SHORT_PREFIX:="加工材料不足"

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
	func objects()->Dictionary:
		var o=session.snapshot.get("objects",{})
		return o if o is Dictionary else {}
	func obj(cell:Vector2i)->Dictionary:
		var o=objects().get("%d,%d"%[cell.x,cell.y])
		return o if o is Dictionary else {}
	func hoist()->Variant:
		return session.snapshot.get("mine_depths",{}).get("hoist",null)

var checks:=0
var failures:=0
var serial:=0
var folder:=""
var save_path:=""
var server
var server_branch:Node
var finished:=false

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
	Engine.time_scale=1.0
	print("GLASS_FURNACE_SESSION watchdog fired before completion")
	print("GLASS_FURNACE_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
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
		print("GLASS_FURNACE_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("GLASS_FURNACE_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("GLASS_FURNACE_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

# ---------------------------------------------------------------- fixture --

static func k(p:Vector2i)->String:
	return "%d,%d"%[p.x,p.y]

func seed_fixture()->bool:
	folder=OS.get_environment("TEMP").path_join("glass-furnace-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if DirAccess.make_dir_recursive_absolute(folder)!=OK:return false
	save_path=folder.path_join("world.json")
	var w:=World.new()
	w.save_path=save_path
	w.state["picnic"]=true
	w.state["mine_depths"]={"unlocked":6,"ready":{},"pumped":24,"hoist":false}
	w.switch_region(SURFACE)
	var spot:=w.safe_arrival(SURFACE_ARRIVAL)
	w.switch_region(Regions.HOME)
	if not expect(spot!=Vector2.ZERO,"surface arrival spot exists"):return false
	for cell in [FURNACE,CHEST]:
		var clear:bool=w.is_land(cell) and not w.water(cell) and not w.protected(cell) and not w.blocked(cell) and w.resource(cell)==""
		for layer in ["objects","ground","roofs","crops","forest"]:
			if w.state[layer].has(k(cell)):clear=false
		if not expect(clear,"fixture cell %s is clear home land"%k(cell)):return false
	for token in [ALPHA,BETA,MENDER]:
		w.add_player(token,{ALPHA:"alpha",BETA:"beta",MENDER:"mender"}[token])
		var p:Dictionary=w.state.players[token]
		if token==MENDER:
			p["region"]=SURFACE
			p["x"]=spot.x
			p["y"]=spot.y
			p["inventory"]=Mines.HOIST_COST.duplicate()
			continue
		var at:Vector2=STAND_A if token==ALPHA else STAND_B
		if not expect(w.can_stand(at),"%s can stand at %s"%[p.name,str(at)]):return false
		p["x"]=at.x
		p["y"]=at.y
		if token==ALPHA:
			p["inventory"]={"stone":25,"iron_ingot":6,"crystal_sand":3,"wood":22,"vein_quartz":2}
		else:
			p["inventory"]={"stone":25,"iron_ingot":6,"crystal_sand":3,"wood":1}
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
	server=Session.new()
	server_branch.add_child(server)
	for attempt in 8:
		var port:=randi_range(31000,58000)
		if server.host(port,"",save_path,KEY,"127.0.0.1",true,"websocket")==OK:return port
	return 0

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
	await create_timer(seconds,true,false,true).timeout

func walk_to(c:Client,target:Vector2)->bool:
	var deadline:=Time.get_ticks_msec()+6000
	while Time.get_ticks_msec()<deadline and c.pos().distance_to(target)>0.22:
		c.session.input_direction((target-c.pos()).limit_length(0.8))
		await pause(0.05)
	c.session.input_direction(Vector2.ZERO)
	return c.pos().distance_to(target)<=0.22

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

## Lets world time run fast on the live server until `condition` holds.
func fast_forward(condition:Callable,seconds:float)->bool:
	Engine.time_scale=TIME_SCALE
	var ok:=await wait_until(condition,seconds)
	Engine.time_scale=1.0
	await pause(0.2)
	return ok

# ---------------------------------------------------------------- helpers --

## Canonical bag: String keys, int values, zero entries dropped.
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

func furnace(c:Client)->Dictionary:
	return c.obj(FURNACE)

func queue_of(c:Client)->Dictionary:
	var q=furnace(c).get("processing",{})
	return q if q is Dictionary else {}

func lane(c:Client,name:String)->Array:
	var l=queue_of(c).get(name,[])
	return l if l is Array else []

func active_kind(c:Client)->String:
	var a=queue_of(c).get("active",{})
	return str(a.get("kind","")) if a is Dictionary else ""

func kinds(list:Array)->Array:
	return list.map(func(e):return str(e.get("kind","")) if e is Dictionary else "?")

## Exact refusal and nothing changed in the refuser's bag, the furnace, the
## chest, or (for `watchers`) any other client's view of them.
func refuse(c:Client,action:String,p:Vector2i,extra:String,message:String,label:String,prefix:bool=false,watchers:Array=[])->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var bags:Array=everyone.map(func(x):return canon(x.bag()))
	var views:Array=everyone.map(func(x):return text([furnace(x),x.obj(CHEST)]))
	var r:=await act(c,action,p,extra)
	var matches:bool=str(r.message).begins_with(message) if prefix else str(r.message)==message
	expect(r.replied and not r.ok and matches,"%s: refused with %s'%s' (got replied=%s ok=%s '%s')"%[label,"prefix " if prefix else "",message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	var same:=true
	for i in everyone.size():
		if canon(everyone[i].bag())!=bags[i] or text([furnace(everyone[i]),everyone[i].obj(CHEST)])!=views[i]:same=false
	expect(same,"%s: every bag, the furnace and the chest unchanged in all watching snapshots"%label)

func sourced_wire(c:Client,recipe_id:String)->Dictionary:
	var id:=""
	for cand in Sources.candidates(c.objects(),c.session.own_id,FURNACE):
		if str(cand.cell)==k(CHEST):id=str(cand.id)
	var recipe:Dictionary=World.processing_recipes("glass_furnace").get(recipe_id,{})
	var plan:Dictionary=Supply.plan(recipe.get("ingredients",{}),c.bag(),c.obj(CHEST).get("items",{}))
	if id.length()!=Sources.ID_LENGTH or not plan.ok:return {"ok":false,"id":id,"plan":plan}
	var digest:=Sources.digest("queue_processing","glass_furnace",k(FURNACE),recipe_id,recipe,k(CHEST),id,plan)
	return {"ok":true,"id":id,"wire":Sources.encode(recipe_id,k(CHEST),id,digest),
		"from_backpack":canon(plan.from_backpack),"from_chest":canon(plan.from_chest)}

# --------------------------------------------------------------- scenario --

var alpha:Client
var beta:Client
var gamma:Client
var mender:Client

func scenario()->bool:
	if not expect(seed_fixture(),"SEEDED FIXTURE written to TEMP and accepted by SaveSchema.validate"):return false
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
	print("GLASS_FURNACE_SESSION_LABEL machine=single process=single transport=%s loopback=127.0.0.1:%d clients=2(+mender,+late joiner) fixture=SEEDED(unlocked=6,hoist=false,positions,bags) clock=Engine.time_scale %.0fx during waits shutdown=normal-only(not crash durability)"%["websocket" if ws else "UNEXPECTED",port,TIME_SCALE])

	# 1. Build locked before the hoist repair, for both islanders.
	for c in [alpha,beta]:
		expect(c.region()==Regions.HOME,"%s starts at home (seeded)"%c.label)
		expect(c.hoist()==false,"%s snapshot carries hoist=false"%c.label)
		expect(c.pos().distance_to(Vector2(FURNACE)+Vector2(0.5,0.5))<=3.2,"%s stands within reach of the furnace cell"%c.label)
	for c in [alpha,beta]:
		await refuse(c,"build",FURNACE,"glass_furnace",World.GLASS_FURNACE_LOCKED_MSG,"%s builds the furnace before the hoist repair"%c.label,false,[alpha if c==beta else beta])
		expect(furnace(alpha).is_empty() and furnace(beta).is_empty(),"no furnace object after %s's refused build"%c.label)
	# Real repair by a third islander on the jinguashi surface.
	mender=await join("mender",MENDER,port)
	expect(joined(mender) and mender.region()==SURFACE,"mender joins on the jinguashi surface")
	if not joined(mender):return false
	var mender_bag:=canon(mender.bag())
	var fixed:=await act(mender,World.HOIST_ACTION,Mines.ENTRY)
	expect(fixed.ok and fixed.message==World.HOIST_OK_MSG,"mender repairs the hoist through the network (%s)"%fixed.message)
	expect(canon(mender.bag())==plus(mender_bag,Mines.HOIST_COST,-1),"repair debits exactly HOIST_COST from mender (%s)"%text(canon(mender.bag())))
	await settle([alpha,beta])
	expect(alpha.hoist()==true and beta.hoist()==true,"both home snapshots now carry hoist=true")
	await leave(mender)
	mender=null
	await wait_until(func():return int(beta.session.snapshot.get("room_population",0))==2,4.0)
	var bag_a:=canon(alpha.bag())
	var bag_b:=canon(beta.bag())
	var built:=await act(alpha,"build",FURNACE,"glass_furnace")
	expect(built.ok,"alpha builds the glass furnace after the repair (%s)"%built.message)
	await settle([alpha,beta])
	expect(canon(alpha.bag())==plus(bag_a,FURNACE_COST,-1),"build cost %s debited from alpha exactly (bag %s)"%[text(FURNACE_COST),text(canon(alpha.bag()))])
	expect(canon(beta.bag())==bag_b,"beta's bag unchanged by alpha's build")
	for c in [alpha,beta]:
		var f:=furnace(c)
		expect(str(f.get("type",""))=="glass_furnace" and str(f.get("owner",""))==alpha.session.own_id,"%s's snapshot shows alpha's glass furnace at %s"%[c.label,k(FURNACE)])
	if furnace(alpha).is_empty():return false

	# 2. Owner-only queue; alpha queues glass + crystal sand; both see the same queue.
	await refuse(beta,"queue_processing",FURNACE,"glass",OWNER_ONLY_MSG,"beta queues glass on alpha's furnace",false,[alpha])
	await refuse(beta,"claim_processing",FURNACE,"",OWNER_ONLY_MSG,"beta claims from alpha's idle furnace",false,[alpha])
	bag_a=canon(alpha.bag())
	var q1:=await act(alpha,"queue_processing",FURNACE,"glass")
	expect(q1.ok and canon(alpha.bag())==plus(bag_a,GLASS_COST,-1),"alpha queues glass, paying exactly %s (%s)"%[text(GLASS_COST),q1.message])
	bag_a=canon(alpha.bag())
	var q2:=await act(alpha,"queue_processing",FURNACE,"crystal_sand")
	expect(q2.ok and canon(alpha.bag())==plus(bag_a,SAND_COST,-1),"alpha queues crystal sand, paying exactly %s (%s)"%[text(SAND_COST),q2.message])
	await settle([alpha,beta])
	for c in [alpha,beta]:
		expect(active_kind(c)=="glass" and kinds(lane(c,"waiting"))==["crystal_sand"] and lane(c,"ready").is_empty(),"%s sees active glass, waiting crystal sand, nothing ready (%s)"%[c.label,text(queue_of(c))])
	expect(text(furnace(alpha))==text(furnace(beta)),"alpha and beta snapshots carry the identical furnace object")
	await refuse(beta,"queue_processing",FURNACE,"glass",OWNER_ONLY_MSG,"beta queues on alpha's busy furnace",false,[alpha])
	await refuse(alpha,"claim_processing",FURNACE,"",NOT_DONE_PREFIX,"alpha claims before the glass is ready",true,[beta])

	# 5a. alpha disconnects mid-job; the job survives; alpha rejoins.
	var job_view:=text(furnace(beta))
	await leave(alpha)
	expect(await wait_until(func():return int(beta.session.snapshot.get("room_population",0))==1,4.0),"server sees alpha leave (room population 1)")
	await settle([beta])
	expect(active_kind(beta)=="glass" and kinds(lane(beta,"waiting"))==["crystal_sand"] and text(furnace(beta))==job_view,"beta still sees alpha's unchanged job while alpha is away")
	alpha=await join("alpha",ALPHA,port)
	expect(joined(alpha),"alpha rejoins with the same token")
	if not joined(alpha):return false
	await settle([alpha,beta])
	expect(text(furnace(alpha))==job_view and text(furnace(beta))==job_view,"after rejoin both see the same job (active glass, waiting sand)")

	# 3. Time passes; claims.
	expect(await fast_forward(func():return not lane(alpha,"ready").is_empty(),20.0),"glass becomes ready on the live server clock (time scale %.0fx)"%TIME_SCALE)
	await settle([alpha,beta])
	for c in [alpha,beta]:
		expect(kinds(lane(c,"ready"))==["glass"] and active_kind(c)=="crystal_sand","%s sees ready glass and active crystal sand"%c.label)
	await refuse(beta,"claim_processing",FURNACE,"",OWNER_ONLY_MSG,"beta claims alpha's ready glass",false,[alpha])
	expect(not alpha.me().get("greenhouse_glass_crafted",false) and not beta.me().get("greenhouse_glass_crafted",false),"The ready glass does not count before a successful claim")
	bag_a=canon(alpha.bag())
	var claim:=await act(alpha,"claim_processing",FURNACE)
	expect(claim.ok and canon(alpha.bag())==plus(bag_a,{"glass":1}),"alpha claims exactly 1 glass (%s)"%claim.message)
	expect(await wait_until(func():return bool(alpha.me().get("greenhouse_glass_crafted",false)),3.0) and not beta.me().get("greenhouse_glass_crafted",false),"Claiming glass counts toward Xinghe's event for the furnace owner only")
	var after_claim:=canon(alpha.bag())
	var marks:=[alpha.notices.size(),beta.notices.size()]
	alpha.session.request_action.rpc_id(1,alpha.session.counter,"claim_processing",FURNACE,"",alpha.region(),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==marks[0] and canon(alpha.bag())==after_claim,"re-sent identical claim request (same sequence) is dropped: no notice, no second payout")
	await refuse(alpha,"claim_processing",FURNACE,"",NOT_DONE_PREFIX,"a fresh claim while only crystal sand is running",true,[beta])
	expect(await fast_forward(func():return not lane(alpha,"ready").is_empty(),12.0),"crystal sand becomes ready")
	await settle([alpha,beta])
	bag_a=canon(alpha.bag())
	claim=await act(alpha,"claim_processing",FURNACE)
	expect(claim.ok and canon(alpha.bag())==plus(bag_a,{"crystal_sand":3}),"alpha claims exactly 3 crystal sand (%s)"%claim.message)
	await refuse(alpha,"claim_processing",FURNACE,"",EMPTY_SHELF_MSG,"a fresh claim on the empty shelf",false,[beta])
	await settle([alpha,beta])
	for c in [alpha,beta]:
		expect(active_kind(c)=="" and lane(c,"waiting").is_empty() and lane(c,"ready").is_empty(),"%s sees an empty furnace queue"%c.label)

	# 4. Adjacent chest supply.
	bag_a=canon(alpha.bag())
	var chest_built:=await act(alpha,"build",CHEST,"chest")
	expect(chest_built.ok and canon(alpha.bag())==plus(bag_a,CHEST_COST,-1),"alpha builds a shared chest below the furnace (%s)"%chest_built.message)
	for item in ["crystal_sand","crystal_sand","crystal_sand","wood"]:
		var dep:=await act(alpha,"deposit",CHEST,item)
		expect(dep.ok,"alpha deposits 1 %s (%s)"%[item,dep.message])
	await settle([alpha,beta])
	expect(int(canon(alpha.bag()).get("crystal_sand",0))==0 and int(canon(alpha.bag()).get("wood",0))==0,"alpha's backpack holds no crystal sand and no wood (%s)"%text(canon(alpha.bag())))
	for c in [alpha,beta]:
		expect(canon(c.obj(CHEST).get("items",{}))==GLASS_COST,"%s sees the chest holding exactly %s"%[c.label,text(GLASS_COST)])
	await refuse(alpha,"queue_processing",FURNACE,"glass",SHORT_PREFIX,"backpack-only glass with an empty backpack",true,[beta])
	await refuse(beta,Sources.PREPARE_ACTION,FURNACE,k(CHEST),Sources.MSG_PROCESSOR,"beta designates the chest for alpha's furnace",false,[alpha])
	expect(not alpha.obj(CHEST).has("box_id"),"beta's refused prepare assigned no chest identity")
	var prep:=await act(alpha,Sources.PREPARE_ACTION,FURNACE,k(CHEST))
	expect(prep.ok,"alpha designates the adjacent chest as the furnace material source (%s)"%prep.message)
	await settle([alpha,beta])
	var quote:=sourced_wire(alpha,"glass")
	expect(quote.ok and quote.from_backpack.is_empty() and quote.from_chest==GLASS_COST,"alpha's preview: all of %s from the chest (%s)"%[text(GLASS_COST),text(quote)])
	if not quote.ok:return false
	var forged:String=quote.wire
	await refuse(beta,"queue_processing",FURNACE,forged,OWNER_ONLY_MSG,"beta sends alpha's exact sourced wire",false,[alpha])
	bag_a=canon(alpha.bag())
	var sourced:=await act(alpha,"queue_processing",FURNACE,quote.wire)
	expect(sourced.ok,"alpha queues glass supplied from the chest (%s)"%sourced.message)
	await settle([alpha,beta])
	expect(canon(alpha.bag())==bag_a,"alpha's backpack untouched by the sourced queue")
	for c in [alpha,beta]:
		expect(canon(c.obj(CHEST).get("items",{})).is_empty(),"%s sees the chest emptied by exactly %s"%[c.label,text(GLASS_COST)])
		expect(active_kind(c)=="glass","%s sees the chest-supplied glass job active"%c.label)

	# 5b. Normal shutdown, save on disk, restart, rejoin, late joiner.
	await settle([alpha,beta])
	var final_furnace:=text(furnace(alpha))
	var final_chest:=text(alpha.obj(CHEST))
	var final_bags:={ALPHA:canon(alpha.bag()),BETA:canon(beta.bag())}
	expect(text(furnace(beta))==final_furnace,"beta sees the identical furnace before shutdown")
	await leave(alpha)
	await leave(beta)
	expect(server.shutdown(),"server Session shuts down with a final save")
	await pause(0.2)
	server_branch.queue_free()
	var disk=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	expect(disk is Dictionary,"save file parses")
	if not disk is Dictionary:return false
	expect(Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"saved world passes SaveSchema")
	var saved_furnace=disk.get("objects",{}).get(k(FURNACE),{})
	expect(saved_furnace is Dictionary and str(saved_furnace.get("type",""))=="glass_furnace" and str(saved_furnace.get("owner",""))==ALPHA,"save holds alpha's furnace at %s"%k(FURNACE))
	var saved_q=saved_furnace.get("processing",{}) if saved_furnace is Dictionary else {}
	expect(saved_q is Dictionary and str(saved_q.get("active",{}).get("kind",""))=="glass" and (saved_q.get("waiting",[]) as Array).is_empty() and (saved_q.get("ready",[]) as Array).is_empty(),"save holds the active chest-supplied glass job (%s)"%text(saved_q))
	var saved_chest=disk.get("objects",{}).get(k(CHEST),{})
	expect(saved_chest is Dictionary and str(saved_chest.get("type",""))=="chest" and canon(saved_chest.get("items",{})).is_empty() and str(saved_chest.get("box_id","")).length()==Sources.ID_LENGTH,"save holds the emptied chest with its source identity")
	expect(disk.get("mine_depths",{}).get("hoist")==true,"save holds the repaired hoist")
	for token in [ALPHA,BETA]:
		expect(canon(disk.players.get(token,{}).get("inventory",{}))==final_bags[token],"save holds %s's exact bag"%token.left(22))
	var port2:=start_server()
	expect(port2>0,"a new server Session hosts the same save")
	if port2==0:return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	expect(joined(alpha) and joined(beta),"both clients rejoin the restarted server")
	if not joined(alpha) or not joined(beta):return false
	await settle([alpha,beta])
	expect(text(furnace(alpha))==final_furnace and text(furnace(beta))==final_furnace,"both see the identical furnace object after restart")
	expect(text(alpha.obj(CHEST))==final_chest and canon(alpha.bag())==final_bags[ALPHA] and canon(beta.bag())==final_bags[BETA],"chest and both bags identical after restart")
	gamma=await join("gamma",GAMMA,port2)
	expect(joined(gamma),"late joiner gamma joins with a fresh token")
	if not joined(gamma):return false
	expect(gamma.region()==Regions.HOME and gamma.pos().distance_to(World.WANGAN_COAST.FERRY_LANDING)<0.2,"Gamma spawns at the ferry landing")
	if not expect(await walk_to(gamma,Vector2(41.5,30.5)) and await walk_to(gamma,Vector2(41.5,34.5)),"Gamma walks from the ferry to the furnace"):return false
	expect(text(furnace(gamma))==final_furnace,"gamma sees the same furnace object")
	await refuse(gamma,"claim_processing",FURNACE,"",OWNER_ONLY_MSG,"gamma claims from alpha's running furnace",false,[alpha])
	await refuse(gamma,"queue_processing",FURNACE,"glass",OWNER_ONLY_MSG,"gamma queues on alpha's furnace",false,[alpha])
	expect(await fast_forward(func():return not lane(alpha,"ready").is_empty(),20.0),"chest-supplied glass becomes ready after restart")
	await settle([alpha,beta,gamma])
	expect(kinds(lane(gamma,"ready"))==["glass"],"gamma sees the ready glass")
	await refuse(gamma,"claim_processing",FURNACE,"",OWNER_ONLY_MSG,"gamma claims alpha's ready glass",false,[alpha,beta])
	bag_a=canon(alpha.bag())
	claim=await act(alpha,"claim_processing",FURNACE)
	expect(claim.ok and canon(alpha.bag())==plus(bag_a,{"glass":1}),"alpha claims exactly 1 chest-supplied glass after restart (%s)"%claim.message)
	expect(int(canon(alpha.bag()).get("glass",0))==2,"alpha ends with exactly 2 glass")
	return true

func teardown()->void:
	Engine.time_scale=1.0
	for c in [alpha,beta,gamma,mender]:
		if c!=null and is_instance_valid(c.session) and not c.session.shutting_down:
			c.session.shutdown()
	await pause(0.2)
	if server!=null and is_instance_valid(server) and server.world!=null:
		expect(server.shutdown(),"final server shutdown saves cleanly")
	await pause(0.2)
	for c in [alpha,beta,gamma,mender]:
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
