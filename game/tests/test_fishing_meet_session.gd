extends SceneTree
## T071 河岸釣魚會 (fishing meet) two-client Session acceptance over a real dedicated
## server and real WebSocket clients.
##
## LEVEL: one machine, ONE Godot process. Inside the single SceneTree a real
## dedicated server Session listens on a free 127.0.0.1 port with the WebSocket
## transport (WebSocketMultiplayerPeer); separate client Session nodes join it over
## loopback, each in its own branch with its own SceneMultiplayer, so every request,
## notice and snapshot travels the RPC + WebSocket path. Clients only read their own
## received snapshots (data.own_fish_meet, the public data.fish_meet projection and
## the players entries; other players' bags are stripped by Session, so alpha's bag
## is checked in alpha's own snapshot and on disk); the server World is never touched after seeding. The
## on-disk save is read (file only) after alpha disconnects and after each normal
## shutdown.
##
## SEEDED FIXTURE (disclosed; written to a fresh TEMP folder and validated with
## SaveSchema before the server starts): picnic=true; state.time=START_TIME; alpha
## stands at A_SPOT (shore 54,36: sign reach 2.0, 1.0 from the cast cell), beta at
## B_SPOT (shore 54,35: sign reach 3.0); exact bags alpha {carp 2, radish 3, wood 5},
## beta {minnow 1, stone 3}; coins are the add_player default. No fish_meet field is
## ever preset. Late joiner "gamma" uses a fresh token (spawn point). Second short
## run (case 10): a separate save with picnic=false and islander "zeta" at A_SPOT
## holding {radish 2}.
## Everything after the seed goes through client Sessions over the network:
## start/join/leave, fish_start/fish_catch, every refusal, the sequence replay,
## alpha's disconnect, the timeout, reconnects, shutdowns and restarts.
## Clock: world time only advances on the live server. The 3 s fish bite and the
## 300 s deadline are reached with a temporary Engine.time_scale (TIME_SCALE).
## Replay (case 5): the raw `request_action` RPC with an already-used sequence
## number (the earlier fish_catch) while a new line is out; Session drops it.
## NOT covered: multiple processes, cross-machine, TLS/wss, latency/packet loss,
## crash durability (only normal shutdowns with a final save), the 8-player cap,
## GOAL early finish and standard-mode tracking (rule level, test_fishing_meet.gd).
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const MEET=preload("res://scripts/fishing_meet.gd")
const Regions=preload("res://scripts/regions.gd")
const KEY:="fishing-meet-session"
const ALPHA:="fishmeet-session-alpha-token"
const BETA:="fishmeet-session-beta-token"
const GAMMA:="fishmeet-session-gamma-token"
const ZETA:="fishmeet-session-zeta-token"
const START_TIME:=2000.0
const TIME_SCALE:=30.0
const HALF:=Vector2(0.5,0.5)
const A_SPOT:=Vector2(54.5,36.5)
const B_SPOT:=Vector2(54.5,35.5)
const CAST:=Vector2i(55,36)
const ALPHA_BAG:={"carp":2,"radish":3,"wood":5}
const BETA_BAG:={"minnow":1,"stone":3}
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
	func other(id:String)->Dictionary:
		var people=session.snapshot.get("players",{})
		if not people is Dictionary:return {}
		var p=people.get(id,{})
		return p if p is Dictionary else {}
	func region()->String:
		return str(session.snapshot.get("region_id",""))
	func bag()->Dictionary:
		var inv=me().get("inventory",{})
		return inv if inv is Dictionary else {}
	func coins()->int:
		return int(me().get("coins",-1))
	func own()->Dictionary:
		var v=session.snapshot.get("own_fish_meet",null)
		return v if v is Dictionary else {}
	func pub()->Dictionary:
		var v=session.snapshot.get("fish_meet",null)
		return v if v is Dictionary else {}
	func time()->float:
		return float(session.snapshot.get("time",-1.0))

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
	print("FISHING_MEET_SESSION watchdog fired before completion")
	print("FISHING_MEET_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
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
		print("FISHING_MEET_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("FISHING_MEET_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("FISHING_MEET_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

func plan()->bool:
	var probe:=folder.path_join("probe.json")
	if not expect(seed_world(probe,true,{}),"probe fixture saved"):return false
	var w:=World.new()
	if not expect(w.load_world(probe),"probe fixture loads like the server's save"):return false
	expect(MEET.available(w.state) and World.fish_meet_available(w.state),"probe: activity available after the picnic")
	for spot:Vector2 in [A_SPOT,B_SPOT]:
		expect(w.can_stand(spot),"probe: %s is standable"%str(spot))
		expect(spot.distance_to(Vector2(MEET.SIGN)+HALF)<=MEET.SIGN_REACH and spot.distance_to(Vector2(CAST)+HALF)<=3.2,"probe: %s reaches the sign and the cast cell"%str(spot))
	expect(MEET.in_waters(CAST) and w.water(CAST),"probe: the cast cell is river water inside WATERS")
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
	if not parsed is Dictionary or parsed.has("fish_meet"):return false
	for token:String in people:
		if parsed.players.get(token,{}).has("fish_meet"):return false
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

## Waits (accelerated clock) until `c`'s own snapshot shows the fish biting.
func wait_bite(c:Client)->bool:
	return await fast_forward(func():
		var cast=c.me().get("fishing",null)
		return cast is Dictionary and c.time()>=float(cast.get("ready",1.0e18)),5.0)

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

static func species_row(v:Variant)->Dictionary:
	var out:={}
	for kind:String in MEET.KINDS:out[kind]=int(v.get(kind,-1)) if v is Dictionary else -1
	return out

static func norm_last(l:Variant)->Variant:
	if not l is Dictionary:return "<invalid>"
	if l.is_empty():return {}
	return {"round":int(l.get("round",-1)),"records":int(l.get("records",-1)),"species":int(l.get("species",-1)),
		"players":int(l.get("players",-1)),"tickets":int(l.get("tickets",-1)),"reason":str(l.get("reason","")),"keys":l.size()}

## Received own_fish_meet normalised (time-varying seconds_left/cooldown omitted).
static func mrow(v:Dictionary)->Dictionary:
	if v.is_empty():return {"<missing>":true}
	return {"unlocked":v.get("unlocked"),"available":v.get("available"),"round":int(v.get("round",-1)),"active":v.get("active"),
		"goal":int(v.get("goal",-1)),"records":int(v.get("records",-1)),"species":species_row(v.get("species")),
		"joined":v.get("joined"),"caught":int(v.get("caught",-1)),
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
			people[str(id)]={"name":str(e.get("name","")),"caught":int(e.get("caught",-1)),"joined":e.get("joined")}
	return {"round":int(v.get("round",-1)),"active":v.get("active"),"records":int(v.get("records",-1)),
		"goal":int(v.get("goal",-1)),"species":species_row(v.get("species")),"participants":people,"last":norm_last(v.get("last",null))}

static func want_own(round_id:int,active:bool,records:int,joined:bool,caught:int,joined_count:int,roster:int,tickets:int,rounds:int,best:int,last:Dictionary)->Dictionary:
	return {"unlocked":true,"available":true,"round":round_id,"active":active,"goal":MEET.GOAL,"records":records,
		"species":MEET.species_after(round_id,records) if round_id>0 else MEET.fresh_species(),
		"joined":joined,"caught":caught,"joined_count":joined_count,"participants":roster,
		"tickets":tickets,"rounds":rounds,"best":best,"last":norm_last(last)}

static func want_pub(round_id:int,active:bool,records:int,people:Dictionary,last:Dictionary)->Dictionary:
	return {"round":round_id,"active":active,"records":records,"goal":MEET.GOAL,
		"species":MEET.species_after(round_id,records) if round_id>0 else MEET.fresh_species(),"participants":people,"last":norm_last(last)}

static func entry(name:String,caught:int,joined:bool)->Dictionary:
	return {"name":name,"caught":caught,"joined":joined}

func expect_own(c:Client,want:Dictionary,label:String)->bool:
	var got:=text(mrow(c.own()))
	return expect(got==text(want),"%s: %s's own_fish_meet is exactly %s (got %s)"%[label,c.label,text(want),got])

func expect_pub(c:Client,want:Dictionary,label:String)->bool:
	var got:=text(prow(c.pub()))
	return expect(got==text(want),"%s: %s's public fish_meet is exactly %s (got %s)"%[label,c.label,text(want),got])

## Everything a client sees about the bags/progress of itself and the other client.
func marks_of(clients:Array)->Array:
	return clients.map(func(x):
		var row:=[text(canon(x.bag())),x.coins(),int(x.me().get("fish_caught",0)),text(x.me().get("collection",{})),text(mrow(x.own())),text(prow(x.pub()))]
		var people=x.session.snapshot.get("players",{})
		if people is Dictionary:
			var ids:Array=people.keys()
			ids.sort()
			for id in ids:row.append(text(canon(people[id].get("inventory",{}))))
		return row)

## Exact refusal; bags, coins, fishing counters, own and public views unchanged on every end.
func refuse(c:Client,action:String,p:Vector2i,extra:String,message:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var marks:=marks_of(everyone)
	var r:=await act(c,action,p,extra)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	expect(marks_of(everyone)==marks,"%s: every bag, purse, fishing counter, own_fish_meet and public fish_meet unchanged in all watching snapshots"%label)

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
			if not person is Dictionary or person.has("fish_meet") or person.has("own_fish_meet"):clean=false
	expect(clean,"%s: no players entry in %s's snapshot carries fish_meet / own_fish_meet"%[label,c.label])
	var dump:=JSON.stringify(c.session.snapshot)
	expect(dump.count("\"own_fish_meet\"")==1 and dump.count("\"paid_round\"")==0,"%s: %s's snapshot carries exactly one own_fish_meet and no raw personal record"%[label,c.label])
	var leaked:=false
	for o:Client in others+[c]:
		if dump.contains(o.token):leaked=true
	expect(not leaked,"%s: %s's snapshot contains no private token"%[label,c.label])

static func disk_round(state:Variant)->Variant:
	if not state is Dictionary or not state.has("fish_meet"):return null
	var r=state.fish_meet
	if not r is Dictionary:return "<invalid>"
	var keys:Array=r.keys().map(func(k):return str(k))
	keys.sort()
	var people:={}
	for token in r.get("participants",{}):
		var e:Dictionary=r.participants[token]
		people[str(token)]={"caught":int(e.get("caught",-1)),"joined":e.get("joined")}
	return {"keys":keys,"round":int(r.get("round",-1)),"active":r.get("active"),"records":int(r.get("records",-1)),
		"index":int(r.get("index",-1)),"species":species_row(r.get("species")),"participants":people,"last":norm_last(r.get("last",null)),
		"ends_ok":absf(float(r.get("ends",0))-float(r.get("started",0))-MEET.DURATION)<0.01}

static func disk_record(person:Variant)->Variant:
	if not person is Dictionary or not person.has("fish_meet"):return null
	var r=person.fish_meet
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
	folder=OS.get_environment("TEMP").path_join("fishing-meet-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	if not plan():return false
	var k0:=MEET.kind_at(1,0)
	save_path=folder.path_join("world.json")
	var seeded:=seed_world(save_path,true,{ALPHA:{"name":"alpha","at":A_SPOT,"inv":ALPHA_BAG},BETA:{"name":"beta","at":B_SPOT,"inv":BETA_BAG}})
	if not expect(seeded,"SEEDED FIXTURE (picnic, time, positions, bags; no fish_meet fields) written to TEMP and accepted by SaveSchema.validate"):return false
	var port:=start_server()
	expect(port>0,"server Session hosts on 127.0.0.1 with the websocket transport")
	if port==0:return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback and received own_fish_meet + fish_meet")
	if not joined(alpha) or not joined(beta):return false
	var ws:bool=server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and beta.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer
	expect(ws,"server and both clients use WebSocketMultiplayerPeer")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World (snapshots only)")
	await settle([alpha,beta])
	print("FISHING_MEET_SESSION_LABEL machine=single process=single transport=%s loopback=127.0.0.1:%d clients=2(+late joiner,+picnic-less run) fixture=SEEDED(picnic,time=%.0f,positions,bags) first_kind=%s clock=Engine.time_scale %.0fx for the bite and the deadline shutdown=normal-only(not crash durability)"%["websocket" if ws else "UNEXPECTED",port,START_TIME,k0,TIME_SCALE])
	var S:=MEET.SIGN
	var ida:=public_id(ALPHA)
	var idb:=public_id(BETA)

	# 1. Fresh, private views.
	var fresh:=want_own(0,false,0,false,0,0,0,0,0,0,{})
	for c:Client in [alpha,beta]:
		var other:Client=beta if c==alpha else alpha
		expect(c.region()==Regions.HOME and World.fish_meet_available(c.session.snapshot),"%s at home; activity available from its own snapshot"%c.label)
		expect_own(c,fresh,"case 1 fresh")
		expect_pub(c,want_pub(0,false,0,{},{}),"case 1 fresh")
		expect(c.own().get("can_start")==true and c.own().has("sign") and c.own().get("waters") is Array and (c.own().get("waters") as Array).size()==12,"case 1 %s can start; sign and 12 waters cells in the view"%c.label)
		private_check(c,[other],"case 1")
	expect(canon(alpha.bag())==canon(ALPHA_BAG) and canon(beta.bag())==canon(BETA_BAG),"preset bags arrive unchanged in the own snapshots")
	var coins_a0:=alpha.coins()
	var coins_b0:=beta.coins()
	var caught_a0:=int(alpha.me().get("fish_caught",0))
	var collection_a0:=text(alpha.me().get("collection",{}))

	# 2. Refusals before any round.
	await refuse(beta,"fish_meet_join",S,"0",MEET.NOT_ACTIVE,"case 2 beta joins with no round",[alpha])
	await refuse(beta,"fish_meet_leave",S,"",MEET.NOT_ACTIVE,"case 2 beta leaves with no round",[alpha])
	await refuse(alpha,"fish_meet_start",S,"5",MEET.STALE,"case 2 alpha starts with a stale round id",[beta])
	await refuse(alpha,"fish_meet_start",CAST,"0",MEET.WRONG_SIGN,"case 2 alpha starts at the water",[beta])

	# 3. Alpha starts; beta sees the round.
	await succeed(alpha,"fish_meet_start",S,"0","第 1 輪河岸釣魚會開始！在告示牌旁的河面拋竿，5 分鐘內一起記錄 12 筆魚種。釣到的魚記進魚種卡後放回河裡，背包不會變動。","case 3 alpha starts",[beta])
	await settle([alpha,beta])
	expect_own(alpha,want_own(1,true,0,true,0,1,1,0,0,0,{}),"case 3 alpha")
	expect_own(beta,want_own(1,true,0,false,0,1,1,0,0,0,{}),"case 3 beta")
	expect_pub(beta,want_pub(1,true,0,{ida:entry("alpha",0,true)},{}),"case 3 beta")
	expect(float(beta.own().get("seconds_left",0))>290.0,"case 3 about 300 s left (%.1f)"%float(beta.own().get("seconds_left",0)))

	# 4. Refusals and beta's join.
	await refuse(alpha,"fish_meet_start",S,"0",MEET.ALREADY_ACTIVE,"case 4 alpha starts twice",[beta])
	await refuse(beta,"fish_meet_leave",S,"",MEET.NOT_JOINED,"case 4 beta leaves before joining",[alpha])
	await refuse(beta,"fish_meet_join",S,"0",MEET.STALE,"case 4 beta joins with the old round id",[alpha])
	await succeed(beta,"fish_meet_join",S,"1","加入第 1 輪河岸釣魚會！在告示牌旁的河面釣到的魚會記進魚種卡後放回河裡，背包不會變動。","case 4 beta joins",[alpha])
	await refuse(beta,"fish_meet_join",S,"1",MEET.ALREADY_JOINED,"case 4 beta joins twice",[alpha])
	await refuse(alpha,"fish_catch",CAST,"","先對水面拋竿吧","case 4 alpha reels in with no line out",[beta])

	# 5. Alpha casts in WATERS and catches: a meet record, backpack unchanged.
	await succeed(alpha,"fish_start",CAST,"","","case 5 alpha casts into WATERS",[beta])
	expect(await wait_bite(alpha),"case 5 the fish bites (accelerated clock)")
	var cast:Dictionary=alpha.me().get("fishing",{}).duplicate()
	var feedback:=preload("res://scripts/fishing_feedback.gd").new()
	feedback.update(beta.session.snapshot,beta.session.own_id,10.0)
	var audio:=preload("res://scripts/fishing_audio.gd").new()
	audio.update(alpha.session.snapshot,alpha.session.own_id)
	var marks_before:=[text(canon(alpha.bag())),text(canon(beta.other(ida).get("inventory",{})))]
	var reel:=await succeed(alpha,"fish_catch",CAST,"","釣到了%s！記進釣魚會的魚種卡後放回河裡，背包沒有變動。大家記錄了 1 / 12 筆、1 / 4 種。"%MEET.kind_name(k0),"case 5 alpha's catch is a meet record",[beta])
	await settle([alpha,beta])
	var visual:=feedback.reel_for(beta.session.snapshot,ida,cast)
	expect(not visual.is_empty() and visual.fish==k0 and visual.released,"case 5 visitor receives the committed catch-and-release visual with its species")
	feedback.update(beta.session.snapshot,beta.session.own_id,10.1)
	var visiting:=feedback.state_for(ida,float(beta.session.snapshot.time),10.1)
	expect(visiting.get("phase")=="catch" and visiting.get("released",false),"case 5 visitor plays release motion instead of a cancelled cast")
	expect(audio.update(alpha.session.snapshot,alpha.session.own_id)==["fish_release"] and audio.update(alpha.session.snapshot,alpha.session.own_id).is_empty(),"case 5 angler hears one release cue")
	expect_own(alpha,want_own(1,true,1,true,1,2,2,0,0,0,{}),"case 5 alpha")
	expect_own(beta,want_own(1,true,1,true,0,2,2,0,0,0,{}),"case 5 beta")
	for c:Client in [alpha,beta]:
		expect_pub(c,want_pub(1,true,1,{ida:entry("alpha",1,true),idb:entry("beta",0,true)},{}),"case 5 %s sees the shared record"%c.label)
	expect(canon(alpha.bag())==canon(ALPHA_BAG) and text(canon(alpha.bag()))==marks_before[0],"case 5 alpha's own snapshot: backpack unchanged")
	# Other players' bags are private (Session strips them); beta sees alpha's public counters.
	expect(not beta.other(ida).has("inventory") and text(canon(beta.other(ida).get("inventory",{})))==marks_before[1],"case 5 beta's snapshot of alpha carries no bag (private) before or after")
	expect(int(beta.other(ida).get("fish_caught",0))==caught_a0,"case 5 beta's snapshot of alpha: fish_caught unchanged")
	expect(int(alpha.me().get("fish_caught",0))==caught_a0 and text(alpha.me().get("collection",{}))==collection_a0 and alpha.coins()==coins_a0,"case 5 alpha's fish_caught, collection and coins unchanged")
	expect(not alpha.me().has("fishing"),"case 5 alpha's line is reeled in")
	# Replay: a new line is out; re-sending the used fish_catch sequence does nothing.
	await succeed(alpha,"fish_start",CAST,"","","case 5 alpha casts again",[beta])
	expect(await wait_bite(alpha),"case 5 the second fish bites")
	await settle([alpha,beta])
	var counts:=[alpha.notices.size(),beta.notices.size()]
	var before5:=marks_of([alpha,beta])
	alpha.session.request_action.rpc_id(1,int(reel.sequence),"fish_catch",CAST,"",alpha.region(),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==counts[0] and beta.notices.size()==counts[1],"case 5 re-sent catch (same sequence %d) gets no notice"%int(reel.sequence))
	expect(marks_of([alpha,beta])==before5 and alpha.me().has("fishing") and int(alpha.pub().get("records",-1))==1,"case 5 re-sent catch records nothing on either end (line still out, 1 record)")

	# 6. More refusals over the network.
	await refuse(beta,"fish_meet_start",S,"1",MEET.ALREADY_ACTIVE,"case 6 beta starts during the round",[alpha])
	await refuse(beta,"fish_meet_leave",S,"x",MEET.BAD_EXTRA,"case 6 beta leaves with an extra",[alpha])

	# 7. Alpha disconnects mid-round with a line out.
	await leave(alpha)
	alpha=null
	var dropped:=await wait_until(func():
		var e=beta.pub().get("participants",{}).get(ida,{})
		return int(beta.session.snapshot.get("room_population",0))==1 and e is Dictionary and e.get("joined")==false,4.0)
	expect(dropped,"case 7 beta sees alpha leave; alpha out of the round")
	expect_pub(beta,want_pub(1,true,1,{ida:entry("alpha",1,false),idb:entry("beta",0,true)},{}),"case 7 round continues with beta")
	var mid=read_disk()
	expect(mid is Dictionary,"case 7 save readable after alpha's disconnect")
	if mid is Dictionary:
		var dr=disk_round(mid)
		expect(dr is Dictionary and dr.participants.get(ALPHA,{}).get("joined")==false and int(dr.participants.get(ALPHA,{}).get("caught",-1))==1 and dr.active==true and int(dr.records)==1,"case 7 on disk: alpha out with 1 catch, round still active (%s)"%text(dr))
		expect(canon(mid.players.get(ALPHA,{}).get("inventory",{}))==canon(ALPHA_BAG),"case 7 on disk: alpha's inventory unchanged")
		expect(int(mid.players.get(ALPHA,{}).get("fish_caught",0))==caught_a0,"case 7 on disk: alpha's fish_caught unchanged")
		expect(disk_record(mid.players.get(ALPHA,{}))==null,"case 7 on disk: no personal record before settlement")

	# 8. The deadline passes (accelerated clock): offline alpha and beta (0 catches) paid once.
	expect(beta.own().get("active")==true,"guard: round still active before the fast-forward (%.1f s left)"%float(beta.own().get("seconds_left",0)))
	var crossed:=await fast_forward(func():
		var v:=beta.own()
		return v.get("active")==false and v.get("last") is Dictionary and int((v.last as Dictionary).get("round",0))==1,25.0)
	expect(crossed,"case 8 the round times out and settles (time scale %.0fx)"%TIME_SCALE)
	await settle([beta])
	var last:={"round":1,"records":1,"species":1,"players":2,"tickets":1,"reason":"time","finished":-1.0}
	expect_own(beta,want_own(1,false,1,false,0,0,2,1,1,1,last),"case 8 beta (caught nothing) after settlement")
	expect_pub(beta,want_pub(1,false,1,{ida:entry("alpha",1,false),idb:entry("beta",0,false)},last),"case 8 public result")
	expect(canon(beta.bag())==canon(BETA_BAG) and beta.coins()==coins_b0,"case 8 tickets are not items or coins: beta's bag and purse unchanged")
	await pause(0.5)
	expect(int(beta.own().get("tickets",-1))==1,"case 8 later ticks do not pay beta again")
	alpha=await join("alpha",ALPHA,port)
	expect(joined(alpha),"case 8 alpha reconnects with the same token")
	if not joined(alpha):return false
	await settle([alpha,beta])
	expect_own(alpha,want_own(1,false,1,false,1,0,2,1,1,1,last),"case 8 alpha sees the ticket earned while offline")
	expect(canon(alpha.bag())==canon(ALPHA_BAG) and alpha.coins()==coins_a0 and int(alpha.me().get("fish_caught",0))==caught_a0,"case 8 alpha's bag, purse and fish_caught exactly as before joining")
	private_check(alpha,[beta],"case 8 alpha")
	private_check(beta,[alpha],"case 8 beta")
	await refuse(alpha,"fish_meet_leave",S,"",MEET.NOT_ACTIVE,"case 8 alpha leaves after the round ended",[beta])
	var marks8:=marks_of([alpha,beta])
	var cool:=await act(alpha,"fish_meet_start",S,"1")
	expect(cool.replied and not cool.ok and str(cool.message).begins_with("魚種卡正在整理"),"case 8 alpha starts during the cooldown: refused (%s)"%str(cool.message))
	await settle([alpha,beta])
	expect(marks_of([alpha,beta])==marks8,"case 8 cooldown refusal changes nothing on either end")

	# 9. Normal shutdown, exact save, restart, late joiner.
	await settle([alpha,beta])
	var final_own:={ALPHA:text(mrow(alpha.own())),BETA:text(mrow(beta.own()))}
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
	var keys:Array=MEET.KEYS.duplicate()
	keys.sort()
	var want_disk:={"keys":keys,"round":1,"active":false,"records":1,"index":1,"species":MEET.species_after(1,1),
		"participants":{ALPHA:{"caught":1,"joined":false},BETA:{"caught":0,"joined":false}},
		"last":norm_last(last),"ends_ok":true}
	expect(text(disk_round(disk))==text(want_disk),"case 9 save holds the exact round %s (got %s)"%[text(want_disk),text(disk_round(disk))])
	var finished_at:=float(disk.fish_meet.get("last",{}).get("finished",-1))
	expect(finished_at+0.01>=float(disk.fish_meet.get("ends",0)) and absf(float(disk.fish_meet.get("ready",0))-finished_at-MEET.COOLDOWN)<0.01,"case 9 settled at/after the deadline; cooldown ends 60 s later")
	var want_record:={"tickets":1,"rounds":1,"best":1,"paid_round":1,"size":4}
	for token in [ALPHA,BETA]:
		expect(text(disk_record(disk.players.get(token,{})))==text(want_record),"case 9 save holds %s's exact record (got %s)"%[token.get_slice("-",2),text(disk_record(disk.players.get(token,{})))])
	expect(canon(disk.players.get(ALPHA,{}).get("inventory",{}))==canon(ALPHA_BAG) and canon(disk.players.get(BETA,{}).get("inventory",{}))==canon(BETA_BAG),"case 9 save holds both exact bags")
	expect(int(disk.players.get(ALPHA,{}).get("coins",-1))==coins_a0 and int(disk.players.get(BETA,{}).get("coins",-1))==coins_b0,"case 9 save holds both purses")
	expect(int(disk.players.get(ALPHA,{}).get("fish_caught",0))==caught_a0 and not disk.players.get(ALPHA,{}).has("harvest_relay"),"case 9 save: alpha's fish_caught unchanged; no harvest relay record invented")
	var port2:=start_server()
	expect(port2>0,"case 9 a new server Session hosts the same save")
	if port2==0:return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	expect(joined(alpha) and joined(beta),"case 9 both clients rejoin the restarted server")
	if not joined(alpha) or not joined(beta):return false
	await settle([alpha,beta])
	expect(text(mrow(alpha.own()))==final_own[ALPHA],"case 9 alpha's own_fish_meet identical after restart (%s)"%text(mrow(alpha.own())))
	expect(text(mrow(beta.own()))==final_own[BETA],"case 9 beta's own_fish_meet identical after restart (%s)"%text(mrow(beta.own())))
	expect(text(prow(alpha.pub()))==final_pub,"case 9 public fish_meet identical after restart")
	gamma=await join("gamma",GAMMA,port2)
	expect(joined(gamma),"case 9 late joiner gamma joins with a fresh token")
	if not joined(gamma):return false
	await settle([alpha,beta,gamma])
	expect_own(gamma,want_own(1,false,1,false,0,0,2,0,0,0,last),"case 9 late joiner's empty personal record with the shared last result")
	private_check(gamma,[alpha,beta],"case 9 gamma")
	await leave(gamma)
	gamma=null
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 9 restarted server shuts down cleanly")

	# 10. Picnic-less world: fish meet actions refused with LOCKED, nothing written.
	save_path=folder.path_join("locked.json")
	if not expect(seed_world(save_path,false,{ZETA:{"name":"zeta","at":A_SPOT,"inv":ZETA_BAG}}),"case 10 picnic-less fixture written and accepted by SaveSchema"):return false
	var port3:=start_server()
	expect(port3>0,"case 10 picnic-less server hosts")
	if port3==0:return false
	zeta=await join("zeta",ZETA,port3)
	expect(joined(zeta),"case 10 zeta joins the picnic-less world")
	if not joined(zeta):return false
	await settle([zeta])
	expect(zeta.session.snapshot.get("picnic")==false and zeta.own().get("unlocked")==false and zeta.own().get("can_start")==false,"case 10 zeta's snapshot: picnic=false, own_fish_meet locked")
	await refuse(zeta,"fish_meet_start",S,"0",MEET.LOCKED,"case 10 start before the picnic",[])
	await refuse(zeta,"fish_meet_join",S,"0",MEET.LOCKED,"case 10 join before the picnic",[])
	await refuse(zeta,"fish_meet_leave",S,"",MEET.LOCKED,"case 10 leave before the picnic",[])
	expect(canon(zeta.bag())==canon(ZETA_BAG),"case 10 zeta keeps the exact preset bag")
	await leave(zeta)
	zeta=null
	expect(await stop_server(),"case 10 picnic-less server shuts down with a final save")
	var locked=read_disk()
	expect(locked is Dictionary and not locked.has("fish_meet") and locked.players.has(ZETA) and not locked.players[ZETA].has("fish_meet"),"case 10 picnic-less save writes no fish_meet field")
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
