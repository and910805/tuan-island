extends SceneTree
## T071 豐收接力 (harvest relay) two-client Session acceptance over a real
## dedicated server and real WebSocket clients.
##
## LEVEL: one machine, ONE Godot process. Inside the single SceneTree a real
## dedicated server Session listens on a free 127.0.0.1 port with the WebSocket
## transport (WebSocketMultiplayerPeer); separate client Session nodes join it
## over loopback, each in its own branch with its own SceneMultiplayer, so every
## request, notice, movement input and snapshot travels the RPC + WebSocket path.
## Clients only read their own received snapshots (data.own_harvest, the public
## data.harvest_relay projection and their own player entry); the server World is
## never touched after seeding. The on-disk save is read (file only) after alpha
## disconnects and after each normal shutdown.
##
## SEEDED FIXTURE (disclosed; written to a fresh TEMP folder and validated with
## SaveSchema before the server starts): picnic=true; state.time=START_TIME;
## alpha stands at A_SPOT (beside the crate, within sign reach), beta at B_SPOT
## (1.2 tiles from alpha, within sign reach, out of crate reach); exact bags
## alpha {radish 3, carrot 2, wood 5}, beta {lettuce 2, stone 3}; coins are the
## add_player default. No harvest field is ever preset. Late joiner "gamma" uses
## a fresh token (spawn point). Second short run (case 9): a separate save with
## picnic=false and islander "zeta" at A_SPOT holding {radish 2}.
## Everything after the seed goes through client Sessions over the network:
## start/join/pick/pass/sort, every refusal, beta's walk to the baskets (movement
## RPC), the sequence replay, alpha's disconnect while carrying, the timeout,
## reconnects, shutdowns and restarts.
## Clock: world time only advances on the live server; the 180 s deadline is
## crossed with a temporary Engine.time_scale (TIME_SCALE) after alpha left.
## Replay (case 5): the raw `request_action` RPC with an already-used sequence
## number; Session drops it before World.
## NOT covered: multiple processes, cross-machine, TLS/wss, latency/packet loss
## injection, crash durability (only normal shutdowns with a final save), the
## 8-player cap and the GOAL early finish (rule level, test_harvest_relay.gd).
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const HARVEST=preload("res://scripts/harvest_relay.gd")
const Regions=preload("res://scripts/regions.gd")
const KEY:="harvest-relay-session"
const ALPHA:="harvest-session-alpha-token"
const BETA:="harvest-session-beta-token"
const GAMMA:="harvest-session-gamma-token"
const ZETA:="harvest-session-zeta-token"
const START_TIME:=2000.0
const TIME_SCALE:=30.0
const HALF:=Vector2(0.5,0.5)
const A_SPOT:=Vector2(31.5,29.0)
const B_SPOT:=Vector2(31.5,30.2)
const LANE:=Vector2(31.5,31.6)
const LOW_SPOT:=Vector2(31.5,33.5)
const FRUIT_TURN:=Vector2(33.5,32.0)
const FRUIT_SPOT:=Vector2(33.5,33.0)
const ALPHA_BAG:={"radish":3,"carrot":2,"wood":5}
const BETA_BAG:={"lettuce":2,"stone":3}
const ZETA_BAG:={"radish":2}

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
	func coins()->int:
		return int(me().get("coins",-1))
	func own()->Dictionary:
		var v=session.snapshot.get("own_harvest",null)
		return v if v is Dictionary else {}
	func pub()->Dictionary:
		var v=session.snapshot.get("harvest_relay",null)
		return v if v is Dictionary else {}

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
	create_timer(150.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	Engine.time_scale=1.0
	print("HARVEST_RELAY_SESSION watchdog fired before completion")
	print("HARVEST_RELAY_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
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
		print("HARVEST_RELAY_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("HARVEST_RELAY_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("HARVEST_RELAY_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

func plan()->bool:
	var probe:=folder.path_join("probe.json")
	if not expect(seed_world(probe,true,{}),"probe fixture saved"):return false
	var w:=World.new()
	if not expect(w.load_world(probe),"probe fixture loads like the server's save"):return false
	expect(HARVEST.available(w.state) and World.harvest_available(w.state),"probe: activity available after the picnic")
	for spot:Vector2 in [A_SPOT,B_SPOT,LANE,LOW_SPOT,FRUIT_TURN,FRUIT_SPOT]:
		expect(w.can_stand(spot),"probe: %s is standable"%str(spot))
	expect(A_SPOT.distance_to(Vector2(HARVEST.CRATE)+HALF)<=HARVEST.HAND_REACH and A_SPOT.distance_to(Vector2(HARVEST.SIGN)+HALF)<=HARVEST.SIGN_REACH,"alpha's spot reaches crate and sign")
	expect(B_SPOT.distance_to(A_SPOT)<=HARVEST.PASS_REACH and B_SPOT.distance_to(Vector2(HARVEST.SIGN)+HALF)<=HARVEST.SIGN_REACH and B_SPOT.distance_to(Vector2(HARVEST.CRATE)+HALF)>HARVEST.HAND_REACH,"beta's spot: pass reach of alpha, sign reach, not crate reach")
	return failures==0

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
	w.active_tokens.clear()
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.has("harvest_relay"):return false
	for token:String in people:
		if parsed.players.get(token,{}).has("harvest_relay"):return false
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
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty() and not c.own().is_empty() and not c.pub().is_empty()

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

func fast_forward(condition:Callable,seconds:float)->bool:
	Engine.time_scale=TIME_SCALE
	var ok:=await wait_until(condition,seconds)
	Engine.time_scale=1.0
	await pause(0.2)
	return ok

## Walks `c` through `points` with real movement input (server-authoritative).
func walk(c:Client,points:Array)->bool:
	for target:Vector2 in points:
		var deadline:=Time.get_ticks_msec()+8000
		while Time.get_ticks_msec()<deadline:
			var d:Vector2=target-c.pos()
			if d.length()<0.12:break
			c.session.input_direction(d.normalized()*clampf(d.length()/1.2,0.18,1.0))
			await process_frame
		c.session.input_direction(Vector2.ZERO)
		await pause(0.35)
		if c.pos().distance_to(target)>0.25:return false
	return true

# ---------------------------------------------------------------- helpers --

static func canon(d:Variant)->Dictionary:
	var out:={}
	if not d is Dictionary:return {"<invalid>":-1}
	for item in d:
		if int(d[item])!=0:out[str(item)]=int(d[item])
	return out

static func text(d:Variant)->String:
	return JSON.stringify(d,"",true)

static func public_id(token:String)->String:
	return token.sha256_text().left(16)

static func norm_last(l:Variant)->Variant:
	if not l is Dictionary:return "<invalid>"
	if l.is_empty():return {}
	return {"round":int(l.get("round",-1)),"delivered":int(l.get("delivered",-1)),"relays":int(l.get("relays",-1)),
		"players":int(l.get("players",-1)),"tickets":int(l.get("tickets",-1)),"reason":str(l.get("reason","")),"keys":l.size()}

## Received own_harvest normalised (time-varying seconds_left/cooldown omitted).
static func hrow(v:Dictionary)->Dictionary:
	if v.is_empty():return {"<missing>":true}
	return {"unlocked":v.get("unlocked"),"available":v.get("available"),"round":int(v.get("round",-1)),"active":v.get("active"),
		"goal":int(v.get("goal",-1)),"delivered":int(v.get("delivered",-1)),"relays":int(v.get("relays",-1)),
		"joined":v.get("joined"),"carry":str(v.get("carry","?")),"carry_relay":v.get("carry_relay"),
		"joined_count":int(v.get("joined_count",-1)),"participants":(v.get("participants",[]) as Array).size(),
		"tickets":int(v.get("tickets",-1)),"rounds":int(v.get("rounds",-1)),"best":int(v.get("best",-1)),"last":norm_last(v.get("last",null))}

## Received public projection normalised.
static func prow(v:Dictionary)->Dictionary:
	if v.is_empty():return {"<missing>":true}
	var people:={}
	var src=v.get("participants",{})
	if src is Dictionary:
		for id in src:
			var e:Dictionary=src[id]
			people[str(id)]={"name":str(e.get("name","")),"carry":str(e.get("carry","?")),"joined":e.get("joined"),"sorted":int(e.get("sorted",-1)),"passed":int(e.get("passed",-1))}
	return {"round":int(v.get("round",-1)),"active":v.get("active"),"delivered":int(v.get("delivered",-1)),"relays":int(v.get("relays",-1)),
		"goal":int(v.get("goal",-1)),"participants":people,"last":norm_last(v.get("last",null))}

static func want_own(round_id:int,active:bool,delivered:int,relays:int,joined:bool,carry:String,carry_relay:bool,joined_count:int,roster:int,tickets:int,rounds:int,best:int,last:Dictionary)->Dictionary:
	return {"unlocked":true,"available":true,"round":round_id,"active":active,"goal":HARVEST.GOAL,"delivered":delivered,"relays":relays,
		"joined":joined,"carry":carry,"carry_relay":carry_relay,"joined_count":joined_count,"participants":roster,
		"tickets":tickets,"rounds":rounds,"best":best,"last":norm_last(last)}

static func entry(name:String,carry:String,joined:bool,sorted:int,passed:int)->Dictionary:
	return {"name":name,"carry":carry,"joined":joined,"sorted":sorted,"passed":passed}

func expect_own(c:Client,want:Dictionary,label:String)->bool:
	var got:=text(hrow(c.own()))
	return expect(got==text(want),"%s: %s's own_harvest is exactly %s (got %s)"%[label,c.label,text(want),got])

func expect_pub(c:Client,want:Dictionary,label:String)->bool:
	var got:=text(prow(c.pub()))
	return expect(got==text(want),"%s: %s's public harvest_relay is exactly %s (got %s)"%[label,c.label,text(want),got])

static func want_pub(round_id:int,active:bool,delivered:int,relays:int,people:Dictionary,last:Dictionary)->Dictionary:
	return {"round":round_id,"active":active,"delivered":delivered,"relays":relays,"goal":HARVEST.GOAL,"participants":people,"last":norm_last(last)}

func marks_of(clients:Array)->Array:
	return clients.map(func(x):return [text(canon(x.bag())),x.coins(),text(hrow(x.own())),text(prow(x.pub()))])

## Exact refusal; bags, coins, own_harvest and the public projection unchanged on every end.
func refuse(c:Client,action:String,p:Vector2i,extra:String,message:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var marks:=marks_of(everyone)
	var r:=await act(c,action,p,extra)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	expect(marks_of(everyone)==marks,"%s: every bag, purse, own_harvest and public harvest_relay unchanged in all watching snapshots"%label)

func succeed(c:Client,action:String,p:Vector2i,extra:String,message:String,label:String,watchers:Array)->Dictionary:
	var r:=await act(c,action,p,extra)
	expect(r.replied and r.ok and (message.is_empty() or str(r.message)==message),"%s: ok%s (got ok=%s '%s')"%[label,"" if message.is_empty() else " with '%s'"%message,str(r.ok),str(r.message)])
	await settle([c]+watchers)
	return r

## Privacy of `c`'s received snapshot.
func private_check(c:Client,others:Array,label:String)->void:
	var people=c.session.snapshot.get("players",{})
	var clean:=people is Dictionary
	if clean:
		for id in people:
			var person=people[id]
			if not person is Dictionary or person.has("harvest_relay") or person.has("own_harvest"):clean=false
	expect(clean,"%s: no players entry in %s's snapshot carries harvest_relay / own_harvest"%[label,c.label])
	var dump:=JSON.stringify(c.session.snapshot)
	expect(dump.count("\"own_harvest\"")==1 and dump.count("\"paid_round\"")==0,"%s: %s's snapshot carries exactly one own_harvest and no raw personal record"%[label,c.label])
	var leaked:=false
	for o:Client in others+[c]:
		if dump.contains(o.token):leaked=true
	expect(not leaked,"%s: %s's snapshot contains no private token"%[label,c.label])

static func disk_round(state:Variant)->Variant:
	if not state is Dictionary or not state.has("harvest_relay"):return null
	var r=state.harvest_relay
	if not r is Dictionary:return "<invalid>"
	var keys:Array=r.keys().map(func(k):return str(k))
	keys.sort()
	var people:={}
	for token in r.get("participants",{}):
		var e:Dictionary=r.participants[token]
		people[str(token)]={"carry":str(e.get("carry","?")),"relay":e.get("relay"),"sorted":int(e.get("sorted",-1)),"passed":int(e.get("passed",-1)),"joined":e.get("joined")}
	return {"keys":keys,"round":int(r.get("round",-1)),"active":r.get("active"),"delivered":int(r.get("delivered",-1)),"relays":int(r.get("relays",-1)),
		"index":int(r.get("index",-1)),"participants":people,"last":norm_last(r.get("last",null)),
		"ends_ok":absf(float(r.get("ends",0))-float(r.get("started",0))-HARVEST.DURATION)<0.01}

static func disk_record(person:Variant)->Variant:
	if not person is Dictionary or not person.has("harvest_relay"):return null
	var r=person.harvest_relay
	if not r is Dictionary:return "<invalid>"
	return {"tickets":int(r.get("tickets",-1)),"rounds":int(r.get("rounds",-1)),"best":int(r.get("best",-1)),"paid_round":int(r.get("paid_round",-1)),"size":r.size()}

func read_disk()->Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(save_path))

# --------------------------------------------------------------- scenario --

var alpha:Client
var beta:Client
var gamma:Client
var zeta:Client

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("harvest-relay-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	if not plan():return false
	var k0:=HARVEST.kind_at(1,0)
	var k1:=HARVEST.kind_at(1,1)
	var b0:=HARVEST.basket_of(k0)
	var wrong:={"root":"leaf","leaf":"root","fruit":"leaf"}[b0] as String
	var route:Array=[LANE,FRUIT_TURN,FRUIT_SPOT] if b0=="fruit" else [LANE,LOW_SPOT]
	save_path=folder.path_join("world.json")
	var seeded:=seed_world(save_path,true,{ALPHA:{"name":"alpha","at":A_SPOT,"inv":ALPHA_BAG},BETA:{"name":"beta","at":B_SPOT,"inv":BETA_BAG}})
	if not expect(seeded,"SEEDED FIXTURE (picnic, time, positions, bags; no harvest fields) written to TEMP and accepted by SaveSchema.validate"):return false
	var port:=start_server()
	expect(port>0,"server Session hosts on 127.0.0.1 with the websocket transport")
	if port==0:return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback and received own_harvest + harvest_relay")
	if not joined(alpha) or not joined(beta):return false
	var ws:bool=server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and beta.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer
	expect(ws,"server and both clients use WebSocketMultiplayerPeer")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World (snapshots only)")
	await settle([alpha,beta])
	print("HARVEST_RELAY_SESSION_LABEL machine=single process=single transport=%s loopback=127.0.0.1:%d clients=2(+late joiner,+picnic-less run) fixture=SEEDED(picnic,time=%.0f,positions,bags) first_kind=%s basket=%s clock=Engine.time_scale %.0fx for the deadline shutdown=normal-only(not crash durability)"%["websocket" if ws else "UNEXPECTED",port,START_TIME,k0,b0,TIME_SCALE])
	var S:=HARVEST.SIGN
	var C:=HARVEST.CRATE
	var ida:=public_id(ALPHA)
	var idb:=public_id(BETA)

	# 1. Fresh, private views.
	var fresh:=want_own(0,false,0,0,false,"",false,0,0,0,0,0,{})
	for c:Client in [alpha,beta]:
		var other:Client=beta if c==alpha else alpha
		expect(c.region()==Regions.HOME and World.harvest_available(c.session.snapshot),"%s at home; activity available from its own snapshot"%c.label)
		expect_own(c,fresh,"case 1 fresh")
		expect_pub(c,want_pub(0,false,0,0,{},{}),"case 1 fresh")
		expect(c.own().get("can_start")==true,"case 1 %s can start"%c.label)
		private_check(c,[other],"case 1")
	expect(canon(alpha.bag())==canon(ALPHA_BAG) and canon(beta.bag())==canon(BETA_BAG),"preset bags arrive unchanged in the own snapshots")
	var coins_a0:=alpha.coins()
	var coins_b0:=beta.coins()

	# 2. Refusals before any round.
	await refuse(beta,"harvest_join",S,"0",HARVEST.NOT_ACTIVE,"case 2 beta joins with no round",[alpha])
	await refuse(alpha,"harvest_pick",C,"",HARVEST.NOT_ACTIVE,"case 2 alpha picks with no round",[beta])
	await refuse(alpha,"harvest_start",S,"5",HARVEST.STALE,"case 2 alpha starts with a stale round id",[beta])
	await refuse(alpha,"harvest_start",C,"0",HARVEST.WRONG_SIGN,"case 2 alpha starts at the crate",[beta])

	# 3. Alpha starts; beta sees the round.
	await succeed(alpha,"harvest_start",S,"0","第 1 輪豐收接力開始！到菜箱拿模型蔬菜，傳給隊友、分類入籃，3 分鐘內一起完成 24 個。活動道具不會放進背包。","case 3 alpha starts",[beta])
	await settle([alpha,beta])
	expect_own(alpha,want_own(1,true,0,0,true,"",false,1,1,0,0,0,{}),"case 3 alpha")
	expect_own(beta,want_own(1,true,0,0,false,"",false,1,1,0,0,0,{}),"case 3 beta")
	expect_pub(beta,want_pub(1,true,0,0,{ida:entry("alpha","",true,0,0)},{}),"case 3 beta")
	expect(float(beta.own().get("seconds_left",0))>170.0,"case 3 about 180 s left (%.1f)"%float(beta.own().get("seconds_left",0)))

	# 4. Refusals and beta's join.
	await refuse(alpha,"harvest_start",S,"0",HARVEST.ALREADY_ACTIVE,"case 4 alpha starts twice",[beta])
	await refuse(beta,"harvest_leave",C,"",HARVEST.NOT_JOINED,"case 4 beta leaves before joining",[alpha])
	await refuse(beta,"harvest_join",S,"0",HARVEST.STALE,"case 4 beta joins with the old round id",[alpha])
	await succeed(beta,"harvest_join",S,"1","加入第 1 輪豐收接力！活動道具只在活動裡使用，不會放進背包。","case 4 beta joins",[alpha])
	await refuse(beta,"harvest_join",S,"1",HARVEST.ALREADY_JOINED,"case 4 beta joins twice",[alpha])
	await refuse(alpha,"harvest_pass",C,"",HARVEST.EMPTY_HANDS,"case 4 alpha passes empty-handed",[beta])
	await refuse(beta,"harvest_pick",C,"",HARVEST.TOO_FAR_CRATE,"case 4 beta picks from out of crate reach",[alpha])

	# 5. Alpha picks; replay of the pick's sequence after passing.
	var pick:=await succeed(alpha,"harvest_pick",C,"","拿到%s，送到「%s」籃，或傳給隊友。"%[HARVEST.kind_name(k0),HARVEST.BASKET_NAMES[b0]],"case 5 alpha picks",[beta])
	await settle([alpha,beta])
	expect_own(alpha,want_own(1,true,0,0,true,k0,false,2,2,0,0,0,{}),"case 5 alpha carries %s"%k0)
	expect_pub(beta,want_pub(1,true,0,0,{ida:entry("alpha",k0,true,0,0),idb:entry("beta","",true,0,0)},{}),"case 5 beta sees alpha carrying")
	expect(canon(alpha.bag())==canon(ALPHA_BAG),"case 5 the model vegetable is not in alpha's bag")
	await refuse(alpha,"harvest_pick",C,"",HARVEST.HANDS_FULL,"case 5 alpha picks with full hands",[beta])
	await succeed(alpha,"harvest_pass",C,"","把%s傳給beta。"%HARVEST.kind_name(k0),"case 5 alpha passes to beta",[beta])
	await settle([alpha,beta])
	expect_own(alpha,want_own(1,true,0,0,true,"",false,2,2,0,0,0,{}),"case 5 alpha after passing")
	expect_own(beta,want_own(1,true,0,0,true,k0,true,2,2,0,0,0,{}),"case 5 beta holds the relayed vegetable")
	var marks:=[alpha.notices.size(),beta.notices.size()]
	var before5:=marks_of([alpha,beta])
	alpha.session.request_action.rpc_id(1,int(pick.sequence),"harvest_pick",C,"",alpha.region(),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==marks[0] and beta.notices.size()==marks[1],"case 5 re-sent pick (same sequence %d) gets no notice"%int(pick.sequence))
	expect(marks_of([alpha,beta])==before5,"case 5 re-sent pick changes nothing on either end (alpha still empty-handed)")

	# 6. Beta walks to the baskets (real movement input) and sorts.
	var walked:=await walk(beta,route)
	expect(walked,"case 6 beta walked to %s (at %s)"%[str(route.back()),str(beta.pos())])
	if not walked:return false
	await refuse(beta,"harvest_sort",HARVEST.BASKETS[wrong],"",HARVEST.WRONG_BASKET%[HARVEST.kind_name(k0),HARVEST.BASKET_NAMES[b0],HARVEST.BASKET_NAMES[b0]],"case 6 beta sorts into the wrong basket (%s)"%wrong,[alpha])
	await refuse(alpha,"harvest_sort",HARVEST.BASKETS[b0],"",HARVEST.TOO_FAR_BASKET,"case 6 alpha sorts from the crate",[beta])
	await succeed(beta,"harvest_sort",HARVEST.BASKETS[b0],"","%s放進「%s」籃（接力加分 +1）！大家完成了 1 / 24。"%[HARVEST.kind_name(k0),HARVEST.BASKET_NAMES[b0]],"case 6 beta sorts into %s"%b0,[alpha])
	await settle([alpha,beta])
	expect_own(beta,want_own(1,true,1,1,true,"",false,2,2,0,0,0,{}),"case 6 beta after sorting")
	expect_pub(alpha,want_pub(1,true,1,1,{ida:entry("alpha","",true,0,1),idb:entry("beta","",true,1,0)},{}),"case 6 alpha sees delivered 1 with a relay")
	expect(canon(alpha.bag())==canon(ALPHA_BAG) and canon(beta.bag())==canon(BETA_BAG) and alpha.coins()==coins_a0 and beta.coins()==coins_b0,"case 6 bags and purses untouched by the activity")

	# 7. Alpha picks again and disconnects while carrying.
	await succeed(alpha,"harvest_pick",C,"","拿到%s，送到「%s」籃，或傳給隊友。"%[HARVEST.kind_name(k1),HARVEST.BASKET_NAMES[HARVEST.basket_of(k1)]],"case 7 alpha picks a second vegetable",[beta])
	await settle([alpha,beta])
	expect(beta.pub().get("participants",{}).get(ida,{}).get("carry","")==k1,"case 7 beta sees alpha carrying %s"%k1)
	await leave(alpha)
	alpha=null
	var dropped:=await wait_until(func():
		var e=beta.pub().get("participants",{}).get(ida,{})
		return int(beta.session.snapshot.get("room_population",0))==1 and e is Dictionary and e.get("carry","?")=="" and e.get("joined")==false,4.0)
	expect(dropped,"case 7 beta sees alpha leave; alpha's vegetable dropped and alpha out of the round")
	expect_pub(beta,want_pub(1,true,1,1,{ida:entry("alpha","",false,0,1),idb:entry("beta","",true,1,0)},{}),"case 7 round continues with beta")
	var mid=read_disk()
	expect(mid is Dictionary,"case 7 save readable after alpha's disconnect")
	if mid is Dictionary:
		var dr=disk_round(mid)
		expect(dr is Dictionary and dr.participants.get(ALPHA,{}).get("carry","?")=="" and dr.participants.get(ALPHA,{}).get("joined")==false and dr.active==true,"case 7 on disk: alpha's carry dropped, round still active (%s)"%text(dr))
		expect(canon(mid.players.get(ALPHA,{}).get("inventory",{}))==canon(ALPHA_BAG),"case 7 on disk: alpha's inventory unchanged")
		expect(disk_record(mid.players.get(ALPHA,{}))==null,"case 7 on disk: no personal record before settlement")

	# 8. The deadline passes (accelerated clock): offline alpha and beta paid once.
	expect(beta.own().get("active")==true,"guard: round still active before the fast-forward (%.1f s left)"%float(beta.own().get("seconds_left",0)))
	var crossed:=await fast_forward(func():
		var v:=beta.own()
		return v.get("active")==false and v.get("last") is Dictionary and int((v.last as Dictionary).get("round",0))==1,25.0)
	expect(crossed,"case 8 the round times out and settles (time scale %.0fx)"%TIME_SCALE)
	await settle([beta])
	# "finished" is time-dependent: norm_last only counts it as a key (checked on disk below).
	var last:={"round":1,"delivered":1,"relays":1,"players":2,"tickets":1,"reason":"time","finished":-1.0}
	expect_own(beta,want_own(1,false,1,1,false,"",false,0,2,1,1,1,last),"case 8 beta after settlement")
	expect_pub(beta,want_pub(1,false,1,1,{ida:entry("alpha","",false,0,1),idb:entry("beta","",false,1,0)},last),"case 8 public result")
	expect(canon(beta.bag())==canon(BETA_BAG) and beta.coins()==coins_b0,"case 8 tickets are not items or coins: beta's bag and purse unchanged")
	await pause(0.5)
	expect(int(beta.own().get("tickets",-1))==1,"case 8 later ticks do not pay beta again")
	alpha=await join("alpha",ALPHA,port)
	expect(joined(alpha),"case 8 alpha reconnects with the same token")
	if not joined(alpha):return false
	await settle([alpha,beta])
	expect_own(alpha,want_own(1,false,1,1,false,"",false,0,2,1,1,1,last),"case 8 alpha sees the ticket earned while offline")
	expect(canon(alpha.bag())==canon(ALPHA_BAG) and alpha.coins()==coins_a0,"case 8 alpha's bag and purse exactly as before joining")
	private_check(alpha,[beta],"case 8 alpha")
	private_check(beta,[alpha],"case 8 beta")
	await refuse(alpha,"harvest_pick",C,"",HARVEST.NOT_ACTIVE,"case 8 alpha picks after the round ended",[beta])

	# 9a. Normal shutdown, exact save, restart, late joiner.
	await settle([alpha,beta])
	var final_own:={ALPHA:text(hrow(alpha.own())),BETA:text(hrow(beta.own()))}
	var final_pub:=text(prow(beta.pub()))
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 9 server Session shuts down with a final save")
	var disk=read_disk()
	expect(disk is Dictionary,"case 9 save file parses")
	if not disk is Dictionary:return false
	expect(Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"case 9 saved world passes SaveSchema")
	var keys:Array=HARVEST.KEYS.duplicate()
	keys.sort()
	var want_disk:={"keys":keys,"round":1,"active":false,"delivered":1,"relays":1,"index":2,
		"participants":{ALPHA:{"carry":"","relay":false,"sorted":0,"passed":1,"joined":false},BETA:{"carry":"","relay":false,"sorted":1,"passed":0,"joined":false}},
		"last":norm_last(last),"ends_ok":true}
	expect(text(disk_round(disk))==text(want_disk),"case 9 save holds the exact round %s (got %s)"%[text(want_disk),text(disk_round(disk))])
	var finished_at:=float(disk.harvest_relay.get("last",{}).get("finished",-1))
	expect(finished_at+0.01>=float(disk.harvest_relay.get("ends",0)) and absf(float(disk.harvest_relay.get("ready",0))-finished_at-HARVEST.COOLDOWN)<0.01,"case 9 settled at/after the deadline; cooldown ends 60 s later")
	var want_record:={"tickets":1,"rounds":1,"best":1,"paid_round":1,"size":4}
	for token in [ALPHA,BETA]:
		expect(text(disk_record(disk.players.get(token,{})))==text(want_record),"case 9 save holds %s's exact record (got %s)"%[token.get_slice("-",2),text(disk_record(disk.players.get(token,{})))])
	expect(canon(disk.players.get(ALPHA,{}).get("inventory",{}))==canon(ALPHA_BAG) and canon(disk.players.get(BETA,{}).get("inventory",{}))==canon(BETA_BAG),"case 9 save holds both exact bags")
	expect(int(disk.players.get(ALPHA,{}).get("coins",-1))==coins_a0 and int(disk.players.get(BETA,{}).get("coins",-1))==coins_b0,"case 9 save holds both purses")
	var port2:=start_server()
	expect(port2>0,"case 9 a new server Session hosts the same save")
	if port2==0:return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	expect(joined(alpha) and joined(beta),"case 9 both clients rejoin the restarted server")
	if not joined(alpha) or not joined(beta):return false
	await settle([alpha,beta])
	expect(text(hrow(alpha.own()))==final_own[ALPHA],"case 9 alpha's own_harvest identical after restart (%s)"%text(hrow(alpha.own())))
	expect(text(hrow(beta.own()))==final_own[BETA],"case 9 beta's own_harvest identical after restart (%s)"%text(hrow(beta.own())))
	expect(text(prow(alpha.pub()))==final_pub,"case 9 public harvest_relay identical after restart")
	gamma=await join("gamma",GAMMA,port2)
	expect(joined(gamma),"case 9 late joiner gamma joins with a fresh token")
	if not joined(gamma):return false
	await settle([alpha,beta,gamma])
	expect_own(gamma,want_own(1,false,1,1,false,"",false,0,2,0,0,0,last),"case 9 late joiner's fresh personal record with the shared last result")
	private_check(gamma,[alpha,beta],"case 9 gamma")
	await leave(gamma)
	gamma=null
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 9 restarted server shuts down cleanly")

	# 10. Picnic-less world: harvest actions refused with LOCKED, nothing written.
	save_path=folder.path_join("locked.json")
	if not expect(seed_world(save_path,false,{ZETA:{"name":"zeta","at":A_SPOT,"inv":ZETA_BAG}}),"case 10 picnic-less fixture written and accepted by SaveSchema"):return false
	var port3:=start_server()
	expect(port3>0,"case 10 picnic-less server hosts")
	if port3==0:return false
	zeta=await join("zeta",ZETA,port3)
	expect(joined(zeta),"case 10 zeta joins the picnic-less world")
	if not joined(zeta):return false
	await settle([zeta])
	expect(zeta.session.snapshot.get("picnic")==false and zeta.own().get("unlocked")==false and zeta.own().get("can_start")==false,"case 10 zeta's snapshot: picnic=false, own_harvest locked")
	await refuse(zeta,"harvest_start",S,"0",HARVEST.LOCKED,"case 10 start before the picnic",[])
	await refuse(zeta,"harvest_join",S,"0",HARVEST.LOCKED,"case 10 join before the picnic",[])
	await refuse(zeta,"harvest_pick",C,"",HARVEST.LOCKED,"case 10 pick before the picnic",[])
	expect(canon(zeta.bag())==canon(ZETA_BAG),"case 10 zeta keeps the exact preset bag")
	await leave(zeta)
	zeta=null
	expect(await stop_server(),"case 10 picnic-less server shuts down with a final save")
	var locked=read_disk()
	expect(locked is Dictionary and not locked.has("harvest_relay") and locked.players.has(ZETA) and not locked.players[ZETA].has("harvest_relay"),"case 10 picnic-less save writes no harvest field")
	if locked is Dictionary:
		expect(canon(locked.players.get(ZETA,{}).get("inventory",{}))==canon(ZETA_BAG),"case 10 picnic-less save keeps zeta's exact bag")
	return true

func teardown()->void:
	Engine.time_scale=1.0
	for c in [alpha,beta,gamma,zeta]:
		if c!=null and is_instance_valid(c.session) and not c.session.shutting_down:
			c.session.shutdown()
	await pause(0.2)
	if server!=null and is_instance_valid(server) and server.world!=null:
		expect(server.shutdown(),"final server shutdown saves cleanly")
	await pause(0.2)
	for c in [alpha,beta,gamma,zeta]:
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
