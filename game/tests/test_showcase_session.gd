extends SceneTree
## T071 家園布置題 (home decoration challenge) two-client Session acceptance over a real
## dedicated server and real WebSocket clients.
##
## LEVEL: one machine, ONE Godot process. Inside the single SceneTree a real
## dedicated server Session listens on a free 127.0.0.1 port with the WebSocket
## transport (WebSocketMultiplayerPeer); separate client Session nodes join it over
## loopback, each in its own branch with its own SceneMultiplayer, so every request,
## notice and snapshot travels the RPC + WebSocket path. Clients only read their own
## received snapshots (data.own_showcase, the public data.showcase projection and the
## players entries; other players' bags are stripped by Session, so alpha's bag is
## checked in alpha's own snapshot and on disk); the server World is never touched
## after seeding. The on-disk save is read (file only) after alpha disconnects and
## after each normal shutdown.
##
## SEEDED FIXTURE (disclosed; written to a fresh TEMP folder and validated with
## SaveSchema before the server starts): picnic=true; state.time=START_TIME; alpha
## stands at A_SPOT (on plot tile 27,45: 1.0 from the sign), beta at B_SPOT (on plot
## tile 28,46: 2.24 from the sign); exact bags alpha {carp 2, radish 3, wood 5}, beta
## {lettuce 1, stone 3}; coins are the add_player default. No showcase field is ever
## preset. Late joiner "gamma" uses a fresh token (spawn point). Second short run
## (case 10): a separate save with picnic=false and islander "zeta" at A_SPOT holding
## {radish 2}.
## Everything after the seed goes through client Sessions over the network:
## start/join/leave/place/remove/finish, every refusal, the sequence replay, alpha's
## disconnect, the timeout, the cooldown clearing, reconnects, shutdowns and restarts.
## Clock: world time only advances on the live server. The 600 s deadline and the 60 s
## cooldown are crossed with a temporary Engine.time_scale (TIME_SCALE).
## Replay (case 5): the raw `request_action` RPC re-sent with an already-used sequence
## number (alpha's second place) but a different tile/kind; Session drops it.
## NOT covered: multiple processes, cross-machine, TLS/wss, latency/packet loss,
## crash durability (only normal shutdowns with a final save), the 8-player cap, early
## finish and the full-display bonus (rule level, test_showcase.gd).
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const SHOW=preload("res://scripts/showcase.gd")
const Regions=preload("res://scripts/regions.gd")
const KEY:="showcase-session"
const ALPHA:="showcase-session-alpha-token"
const BETA:="showcase-session-beta-token"
const GAMMA:="showcase-session-gamma-token"
const ZETA:="showcase-session-zeta-token"
const START_TIME:=2000.0
const TIME_SCALE:=30.0
const HALF:=Vector2(0.5,0.5)
const A_SPOT:=Vector2(27.5,45.5)
const B_SPOT:=Vector2(28.5,46.5)
const A_TILE_1:=Vector2i(27,45)
const A_TILE_2:=Vector2i(28,45)
const B_TILE:=Vector2i(28,46)
const EMPTY_TILE:=Vector2i(29,46)
const ALPHA_BAG:={"carp":2,"radish":3,"wood":5}
const BETA_BAG:={"lettuce":1,"stone":3}
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
		var v=session.snapshot.get("own_showcase",null)
		return v if v is Dictionary else {}
	func pub()->Dictionary:
		var v=session.snapshot.get("showcase",null)
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
	create_timer(170.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	Engine.time_scale=1.0
	print("SHOWCASE_SESSION watchdog fired before completion")
	print("SHOWCASE_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
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
		print("SHOWCASE_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("SHOWCASE_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("SHOWCASE_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

func plan()->bool:
	var probe:=folder.path_join("probe.json")
	if not expect(seed_world(probe,true,{}),"probe fixture saved"):return false
	var w:=World.new()
	if not expect(w.load_world(probe),"probe fixture loads like the server's save"):return false
	expect(SHOW.available(w.state) and World.showcase_available(w.state),"probe: activity available after the picnic")
	for spot:Vector2 in [A_SPOT,B_SPOT]:
		expect(w.can_stand(spot),"probe: %s is standable"%str(spot))
		expect(spot.distance_to(Vector2(SHOW.SIGN)+HALF)<=SHOW.SIGN_REACH,"probe: %s reaches the sign"%str(spot))
	for tile:Vector2i in [A_TILE_1,A_TILE_2]:
		expect(SHOW.in_plot(tile) and A_SPOT.distance_to(Vector2(tile)+HALF)<=SHOW.PLACE_REACH,"probe: alpha reaches plot tile %s"%str(tile))
	for tile:Vector2i in [B_TILE,A_TILE_1,EMPTY_TILE]:
		expect(SHOW.in_plot(tile) and B_SPOT.distance_to(Vector2(tile)+HALF)<=SHOW.PLACE_REACH,"probe: beta reaches plot tile %s"%str(tile))
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
	if not parsed is Dictionary or parsed.has("showcase"):return false
	for token:String in people:
		if parsed.players.get(token,{}).has("showcase"):return false
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

static func pieces_row(v:Variant)->Dictionary:
	var out:={}
	if not v is Dictionary:return {"<invalid>":true}
	for tile in v:out[str(tile)]=str(v[tile])
	return out

static func norm_last(l:Variant)->Variant:
	if not l is Dictionary:return "<invalid>"
	if l.is_empty():return {}
	return {"round":int(l.get("round",-1)),"theme":str(l.get("theme","")),"pieces":int(l.get("pieces",-1)),"met":l.get("met"),"full":l.get("full"),
		"players":int(l.get("players",-1)),"tickets":int(l.get("tickets",-1)),"reason":str(l.get("reason","")),"keys":l.size()}

## Received own_showcase normalised (time-varying seconds_left/cooldown/can_start omitted).
static func mrow(v:Dictionary)->Dictionary:
	if v.is_empty():return {"<missing>":true}
	return {"unlocked":v.get("unlocked"),"available":v.get("available"),"round":int(v.get("round",-1)),"active":v.get("active"),
		"theme":str(v.get("theme","?")),"pieces":pieces_row(v.get("pieces")),"pieces_count":int(v.get("pieces_count",-1)),"theme_met":v.get("theme_met"),
		"joined":v.get("joined"),"placed":int(v.get("placed",-1)),"shown":int(v.get("shown",-1)),
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
			people[str(id)]={"name":str(e.get("name","")),"placed":int(e.get("placed",-1)),"shown":int(e.get("shown",-1)),"joined":e.get("joined")}
	return {"round":int(v.get("round",-1)),"active":v.get("active"),"theme":str(v.get("theme","?")),"pieces":pieces_row(v.get("pieces")),
		"pieces_count":int(v.get("pieces_count",-1)),"participants":people,"last":norm_last(v.get("last",null))}

static func want_own(round_id:int,active:bool,pieces:Dictionary,joined:bool,placed:int,shown:int,joined_count:int,roster:int,tickets:int,rounds:int,best:int,last:Dictionary)->Dictionary:
	return {"unlocked":true,"available":true,"round":round_id,"active":active,"theme":SHOW.theme_of(round_id),"pieces":pieces,"pieces_count":pieces.size(),
		"theme_met":false,"joined":joined,"placed":placed,"shown":shown,"joined_count":joined_count,"participants":roster,
		"tickets":tickets,"rounds":rounds,"best":best,"last":norm_last(last)}

static func want_pub(round_id:int,active:bool,pieces:Dictionary,people:Dictionary,last:Dictionary)->Dictionary:
	return {"round":round_id,"active":active,"theme":SHOW.theme_of(round_id),"pieces":pieces,"pieces_count":pieces.size(),"participants":people,"last":norm_last(last)}

static func entry(name:String,placed:int,shown:int,joined:bool)->Dictionary:
	return {"name":name,"placed":placed,"shown":shown,"joined":joined}

func expect_own(c:Client,want:Dictionary,label:String)->bool:
	var got:=text(mrow(c.own()))
	return expect(got==text(want),"%s: %s's own_showcase is exactly %s (got %s)"%[label,c.label,text(want),got])

func expect_pub(c:Client,want:Dictionary,label:String)->bool:
	var got:=text(prow(c.pub()))
	return expect(got==text(want),"%s: %s's public showcase is exactly %s (got %s)"%[label,c.label,text(want),got])

## Everything a client sees about the bags/progress of itself and the other client.
func marks_of(clients:Array)->Array:
	return clients.map(func(x):
		var row:=[text(canon(x.bag())),x.coins(),text(mrow(x.own())),text(prow(x.pub()))]
		var people=x.session.snapshot.get("players",{})
		if people is Dictionary:
			var ids:Array=people.keys()
			ids.sort()
			for id in ids:row.append(text(canon(people[id].get("inventory",{}))))
		return row)

## Exact refusal; bags, coins, own and public views unchanged on every end.
func refuse(c:Client,action:String,p:Vector2i,extra:String,message:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var marks:=marks_of(everyone)
	var r:=await act(c,action,p,extra)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	expect(marks_of(everyone)==marks,"%s: every bag, purse, own_showcase and public showcase unchanged in all watching snapshots"%label)

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
			if not person is Dictionary or person.has("showcase") or person.has("own_showcase"):clean=false
	expect(clean,"%s: no players entry in %s's snapshot carries showcase / own_showcase"%[label,c.label])
	var dump:=JSON.stringify(c.session.snapshot)
	expect(dump.count("\"own_showcase\"")==1 and dump.count("\"paid_round\"")==0,"%s: %s's snapshot carries exactly one own_showcase and no raw personal record"%[label,c.label])
	var bare:=true
	for source in [c.pub().get("pieces",{}),c.own().get("pieces",{})]:
		if not source is Dictionary:bare=false
		else:
			for tile in source:
				if not source[tile] is String:bare=false
	expect(bare,"%s: %s's pieces are cell -> kind strings only (no placer)"%[label,c.label])
	var leaked:=false
	for o:Client in others+[c]:
		if dump.contains(o.token):leaked=true
	expect(not leaked,"%s: %s's snapshot contains no private token"%[label,c.label])

static func disk_round(state:Variant)->Variant:
	if not state is Dictionary or not state.has("showcase"):return null
	var r=state.showcase
	if not r is Dictionary:return "<invalid>"
	var keys:Array=r.keys().map(func(k):return str(k))
	keys.sort()
	var people:={}
	for token in r.get("participants",{}):
		var e:Dictionary=r.participants[token]
		people[str(token)]={"placed":int(e.get("placed",-1)),"joined":e.get("joined")}
	var pieces:={}
	for tile in r.get("pieces",{}):
		var piece:Dictionary=r.pieces[tile]
		pieces[str(tile)]={"kind":str(piece.get("kind","")),"by":str(piece.get("by",""))}
	return {"keys":keys,"round":int(r.get("round",-1)),"active":r.get("active"),"theme":str(r.get("theme","?")),"pieces":pieces,
		"participants":people,"last":norm_last(r.get("last",null)),"ends_ok":absf(float(r.get("ends",0))-float(r.get("started",0))-SHOW.DURATION)<0.01}

static func disk_record(person:Variant)->Variant:
	if not person is Dictionary or not person.has("showcase"):return null
	var r=person.showcase
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
	folder=OS.get_environment("TEMP").path_join("showcase-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	if not plan():return false
	save_path=folder.path_join("world.json")
	var seeded:=seed_world(save_path,true,{ALPHA:{"name":"alpha","at":A_SPOT,"inv":ALPHA_BAG},BETA:{"name":"beta","at":B_SPOT,"inv":BETA_BAG}})
	if not expect(seeded,"SEEDED FIXTURE (picnic, time, positions, bags; no showcase fields) written to TEMP and accepted by SaveSchema.validate"):return false
	var port:=start_server()
	expect(port>0,"server Session hosts on 127.0.0.1 with the websocket transport")
	if port==0:return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback and received own_showcase + showcase")
	if not joined(alpha) or not joined(beta):return false
	var ws:bool=server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and beta.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer
	expect(ws,"server and both clients use WebSocketMultiplayerPeer")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World (snapshots only)")
	await settle([alpha,beta])
	print("SHOWCASE_SESSION_LABEL machine=single process=single transport=%s loopback=127.0.0.1:%d clients=2(+late joiner,+picnic-less run) fixture=SEEDED(picnic,time=%.0f,positions,bags) clock=Engine.time_scale %.0fx for the deadline and the cooldown shutdown=normal-only(not crash durability)"%["websocket" if ws else "UNEXPECTED",port,START_TIME,TIME_SCALE])
	var S:=SHOW.SIGN
	var ida:=public_id(ALPHA)
	var idb:=public_id(BETA)

	# 1. Fresh, private views.
	var fresh:=want_own(0,false,{},false,0,0,0,0,0,0,0,{})
	for c:Client in [alpha,beta]:
		var other:Client=beta if c==alpha else alpha
		expect(c.region()==Regions.HOME and World.showcase_available(c.session.snapshot),"%s at home; activity available from its own snapshot"%c.label)
		expect_own(c,fresh,"case 1 fresh")
		expect_pub(c,want_pub(0,false,{},{},{}),"case 1 fresh")
		expect(c.own().get("can_start")==true and c.own().get("sign")==S and c.own().get("plot_cells") is Array and (c.own().get("plot_cells") as Array).size()==24 and (c.own().get("kinds") as Array).size()==8,"case 1 %s can start; sign, 24 plot cells and 8 kinds in the view"%c.label)
		private_check(c,[other],"case 1")
	expect(canon(alpha.bag())==canon(ALPHA_BAG) and canon(beta.bag())==canon(BETA_BAG),"preset bags arrive unchanged in the own snapshots")
	var coins_a0:=alpha.coins()
	var coins_b0:=beta.coins()

	# 2. Refusals before any round.
	await refuse(beta,"showcase_join",S,"0",SHOW.NOT_ACTIVE,"case 2 beta joins with no round",[alpha])
	await refuse(beta,"showcase_leave",S,"",SHOW.NOT_ACTIVE,"case 2 beta leaves with no round",[alpha])
	await refuse(alpha,"showcase_start",S,"5",SHOW.STALE,"case 2 alpha starts with a stale round id",[beta])
	await refuse(alpha,"showcase_start",A_TILE_1,"0",SHOW.WRONG_SIGN,"case 2 alpha starts at a plot tile",[beta])
	await refuse(alpha,"showcase_place",A_TILE_1,"0|lantern",SHOW.NOT_ACTIVE,"case 2 alpha places with no round",[beta])

	# 3. Alpha starts; beta sees the round.
	await succeed(alpha,"showcase_start",S,"0","第 1 輪家園布置題開始！本輪主題「花園茶會」：花草 4、座位 3、燈飾 1。10 分鐘內在展示地塊擺好布置道具；道具只在活動裡使用，背包不會變動。","case 3 alpha starts",[beta])
	await settle([alpha,beta])
	expect_own(alpha,want_own(1,true,{},true,0,0,1,1,0,0,0,{}),"case 3 alpha")
	expect_own(beta,want_own(1,true,{},false,0,0,1,1,0,0,0,{}),"case 3 beta")
	expect_pub(beta,want_pub(1,true,{},{ida:entry("alpha",0,0,true)},{}),"case 3 beta")
	expect(float(beta.own().get("seconds_left",0))>590.0,"case 3 about 600 s left (%.1f)"%float(beta.own().get("seconds_left",0)))

	# 4. Refusals and beta's join.
	await refuse(alpha,"showcase_start",S,"0",SHOW.ALREADY_ACTIVE,"case 4 alpha starts twice",[beta])
	await refuse(beta,"showcase_leave",S,"",SHOW.NOT_JOINED,"case 4 beta leaves before joining",[alpha])
	await refuse(beta,"showcase_place",B_TILE,"1|bench",SHOW.NOT_JOINED,"case 4 beta places before joining",[alpha])
	await refuse(beta,"showcase_join",S,"0",SHOW.STALE,"case 4 beta joins with the old round id",[alpha])
	await succeed(beta,"showcase_join",S,"1","加入第 1 輪家園布置題！本輪主題「花園茶會」：花草 4、座位 3、燈飾 1。布置道具只在活動裡使用，背包不會變動。","case 4 beta joins",[alpha])
	await refuse(beta,"showcase_join",S,"1",SHOW.ALREADY_JOINED,"case 4 beta joins twice",[alpha])

	# 5. Alpha places; both ends see it; bags unchanged. Refusals; replay.
	await succeed(alpha,"showcase_place",A_TILE_1,"1|lantern","擺上紙燈籠。「花園茶會」進度：花草 0/4、座位 0/3、燈飾 1/1。","case 5 alpha places a lantern",[beta])
	await settle([alpha,beta])
	var one:={"27,45":"lantern"}
	expect_own(alpha,want_own(1,true,one,true,1,1,2,2,0,0,0,{}),"case 5 alpha")
	expect_own(beta,want_own(1,true,one,true,0,0,2,2,0,0,0,{}),"case 5 beta")
	for c:Client in [alpha,beta]:
		expect_pub(c,want_pub(1,true,one,{ida:entry("alpha",1,1,true),idb:entry("beta",0,0,true)},{}),"case 5 %s sees alpha's piece"%c.label)
	expect(canon(alpha.bag())==canon(ALPHA_BAG) and alpha.coins()==coins_a0,"case 5 alpha's own snapshot: backpack and purse unchanged")
	expect(not beta.other(ida).has("inventory"),"case 5 beta's snapshot of alpha carries no bag (private)")
	await refuse(beta,"showcase_place",A_TILE_1,"1|bench",SHOW.TILE_TAKEN,"case 5 beta places on alpha's tile",[alpha])
	await refuse(beta,"showcase_place",B_TILE,"1|bonfire",SHOW.UNKNOWN_KIND,"case 5 beta places an unknown kind",[alpha])
	await refuse(beta,"showcase_place",Vector2i(33,46),"1|bench",SHOW.OUTSIDE_PLOT,"case 5 beta places outside the plot",[alpha])
	await refuse(beta,"showcase_place",Vector2i(32,47),"1|bench",SHOW.TOO_FAR_TILE,"case 5 beta places too far away",[alpha])
	await refuse(beta,"showcase_place",B_TILE,"0|bench",SHOW.STALE,"case 5 beta places with a stale round id",[alpha])
	await refuse(beta,"showcase_remove",EMPTY_TILE,"1",SHOW.NO_PIECE,"case 5 beta removes an empty tile",[alpha])
	await refuse(beta,"showcase_finish",S,"1",SHOW.NOT_MET,"case 5 beta finishes with the theme unmet",[alpha])
	var second:=await succeed(alpha,"showcase_place",A_TILE_2,"1|flower_pot","","case 5 alpha places a flower pot",[beta])
	await succeed(beta,"showcase_place",B_TILE,"1|bench","","case 5 beta places a bench",[alpha])
	await settle([alpha,beta])
	var three:={"27,45":"lantern","28,45":"flower_pot","28,46":"bench"}
	for c:Client in [alpha,beta]:
		expect_pub(c,want_pub(1,true,three,{ida:entry("alpha",2,2,true),idb:entry("beta",1,1,true)},{}),"case 5 %s sees three pieces"%c.label)
	# Replay: the used sequence of alpha's second place, re-sent with another tile/kind.
	var counts:=[alpha.notices.size(),beta.notices.size()]
	var before5:=marks_of([alpha,beta])
	alpha.session.request_action.rpc_id(1,int(second.sequence),"showcase_place",Vector2i(27,46),"1|stool",alpha.region(),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==counts[0] and beta.notices.size()==counts[1],"case 5 re-sent place (same sequence %d) gets no notice"%int(second.sequence))
	expect(marks_of([alpha,beta])==before5 and int(alpha.pub().get("pieces_count",-1))==3,"case 5 re-sent place changes nothing on either end (still 3 pieces)")

	# 6. More refusals over the network.
	await refuse(beta,"showcase_start",S,"1",SHOW.ALREADY_ACTIVE,"case 6 beta starts during the round",[alpha])
	await refuse(beta,"showcase_leave",S,"x",SHOW.BAD_EXTRA,"case 6 beta leaves with an extra",[alpha])

	# 7. Alpha disconnects mid-round: the round continues and the pieces stay.
	await leave(alpha)
	alpha=null
	var dropped:=await wait_until(func():
		var e=beta.pub().get("participants",{}).get(ida,{})
		return int(beta.session.snapshot.get("room_population",0))==1 and e is Dictionary and e.get("joined")==false,4.0)
	expect(dropped,"case 7 beta sees alpha leave; alpha out of the round")
	expect_pub(beta,want_pub(1,true,three,{ida:entry("alpha",2,2,false),idb:entry("beta",1,1,true)},{}),"case 7 round continues with alpha's pieces on the plot")
	var mid=read_disk()
	expect(mid is Dictionary,"case 7 save readable after alpha's disconnect")
	if mid is Dictionary:
		var dr=disk_round(mid)
		var want_pieces:={"27,45":{"kind":"lantern","by":ALPHA},"28,45":{"kind":"flower_pot","by":ALPHA},"28,46":{"kind":"bench","by":BETA}}
		expect(dr is Dictionary and dr.participants.get(ALPHA,{}).get("joined")==false and int(dr.participants.get(ALPHA,{}).get("placed",-1))==2 and dr.active==true and text(dr.pieces)==text(want_pieces),"case 7 on disk: alpha out with 2 placed, round active, pieces kept with placers (%s)"%text(dr))
		expect(canon(mid.players.get(ALPHA,{}).get("inventory",{}))==canon(ALPHA_BAG),"case 7 on disk: alpha's inventory unchanged")
		expect(disk_record(mid.players.get(ALPHA,{}))==null,"case 7 on disk: no personal record before settlement")

	# 8. The deadline passes (accelerated clock): offline alpha and beta paid once.
	expect(beta.own().get("active")==true,"guard: round still active before the fast-forward (%.1f s left)"%float(beta.own().get("seconds_left",0)))
	var crossed:=await fast_forward(func():
		var v:=beta.own()
		return v.get("active")==false and v.get("last") is Dictionary and int((v.last as Dictionary).get("round",0))==1,45.0)
	expect(crossed,"case 8 the round times out and settles (time scale %.0fx)"%TIME_SCALE)
	await settle([beta])
	var last:={"round":1,"theme":"garden_tea","pieces":3,"met":false,"full":false,"players":2,"tickets":1,"reason":"time","finished":-1.0}
	expect_own(beta,want_own(1,false,three,false,1,1,0,2,1,1,3,last),"case 8 beta after settlement (display still up)")
	expect_pub(beta,want_pub(1,false,three,{ida:entry("alpha",2,2,false),idb:entry("beta",1,1,false)},last),"case 8 public result")
	expect(canon(beta.bag())==canon(BETA_BAG) and beta.coins()==coins_b0,"case 8 tickets are not items or coins: beta's bag and purse unchanged")
	await pause(0.5)
	expect(int(beta.own().get("tickets",-1))==1,"case 8 later ticks do not pay beta again")
	alpha=await join("alpha",ALPHA,port)
	expect(joined(alpha),"case 8 alpha reconnects with the same token")
	if not joined(alpha):return false
	await settle([alpha,beta])
	expect_own(alpha,want_own(1,false,three,false,2,2,0,2,1,1,3,last),"case 8 alpha sees the ticket earned while offline")
	expect(canon(alpha.bag())==canon(ALPHA_BAG) and alpha.coins()==coins_a0,"case 8 alpha's bag and purse exactly as before joining")
	private_check(alpha,[beta],"case 8 alpha")
	private_check(beta,[alpha],"case 8 beta")
	await refuse(alpha,"showcase_leave",S,"",SHOW.NOT_ACTIVE,"case 8 alpha leaves after the round ended",[beta])
	await refuse(alpha,"showcase_place",A_TILE_1,"1|stool",SHOW.NOT_ACTIVE,"case 8 alpha places after the round ended",[beta])
	var marks8:=marks_of([alpha,beta])
	var cool:=await act(alpha,"showcase_start",S,"1")
	expect(cool.replied and not cool.ok and str(cool.message).begins_with("展示地塊正在整理"),"case 8 alpha starts during the cooldown: refused (%s)"%str(cool.message))
	await settle([alpha,beta])
	expect(marks_of([alpha,beta])==marks8,"case 8 cooldown refusal changes nothing on either end")
	# The display is cleared once the cooldown elapses (accelerated clock).
	var cleared:=await fast_forward(func():
		return int(alpha.pub().get("pieces_count",-1))==0 and int(beta.pub().get("pieces_count",-1))==0 and alpha.own().get("can_start")==true,20.0)
	expect(cleared,"case 8 both ends see the plot cleared after the cooldown")
	await settle([alpha,beta])
	expect_own(alpha,want_own(1,false,{},false,2,0,0,2,1,1,3,last),"case 8 alpha after the cooldown")
	expect_pub(beta,want_pub(1,false,{},{ida:entry("alpha",2,0,false),idb:entry("beta",1,0,false)},last),"case 8 public after the cooldown")
	expect(int(alpha.own().get("tickets",-1))==1 and int(beta.own().get("tickets",-1))==1,"case 8 clearing pays nothing")

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
	var keys:Array=SHOW.KEYS.duplicate()
	keys.sort()
	var want_disk:={"keys":keys,"round":1,"active":false,"theme":"garden_tea","pieces":{},
		"participants":{ALPHA:{"placed":2,"joined":false},BETA:{"placed":1,"joined":false}},
		"last":norm_last(last),"ends_ok":true}
	expect(text(disk_round(disk))==text(want_disk),"case 9 save holds the exact round %s (got %s)"%[text(want_disk),text(disk_round(disk))])
	var finished_at:=float(disk.showcase.get("last",{}).get("finished",-1))
	expect(finished_at+0.01>=float(disk.showcase.get("ends",0)) and absf(float(disk.showcase.get("ready",0))-finished_at-SHOW.COOLDOWN)<0.01 and float(disk.get("time",0))>=float(disk.showcase.get("ready",0)),"case 9 settled at/after the deadline; cooldown over on disk")
	var want_record:={"tickets":1,"rounds":1,"best":3,"paid_round":1,"size":4}
	for token in [ALPHA,BETA]:
		expect(text(disk_record(disk.players.get(token,{})))==text(want_record),"case 9 save holds %s's exact record (got %s)"%[token.get_slice("-",2),text(disk_record(disk.players.get(token,{})))])
	expect(canon(disk.players.get(ALPHA,{}).get("inventory",{}))==canon(ALPHA_BAG) and canon(disk.players.get(BETA,{}).get("inventory",{}))==canon(BETA_BAG),"case 9 save holds both exact bags")
	expect(int(disk.players.get(ALPHA,{}).get("coins",-1))==coins_a0 and int(disk.players.get(BETA,{}).get("coins",-1))==coins_b0,"case 9 save holds both purses")
	expect(not disk.players.get(ALPHA,{}).has("fish_meet") and not disk.players.get(ALPHA,{}).has("harvest_relay"),"case 9 save: no other activity record invented")
	var port2:=start_server()
	expect(port2>0,"case 9 a new server Session hosts the same save")
	if port2==0:return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	expect(joined(alpha) and joined(beta),"case 9 both clients rejoin the restarted server")
	if not joined(alpha) or not joined(beta):return false
	await settle([alpha,beta])
	expect(text(mrow(alpha.own()))==final_own[ALPHA],"case 9 alpha's own_showcase identical after restart (%s)"%text(mrow(alpha.own())))
	expect(text(mrow(beta.own()))==final_own[BETA],"case 9 beta's own_showcase identical after restart (%s)"%text(mrow(beta.own())))
	expect(text(prow(alpha.pub()))==final_pub,"case 9 public showcase identical after restart")
	expect(canon(alpha.bag())==canon(ALPHA_BAG),"case 9 alpha's bag unchanged after restart")
	gamma=await join("gamma",GAMMA,port2)
	expect(joined(gamma),"case 9 late joiner gamma joins with a fresh token")
	if not joined(gamma):return false
	await settle([alpha,beta,gamma])
	expect_own(gamma,want_own(1,false,{},false,0,0,0,2,0,0,0,last),"case 9 late joiner's empty personal record with the shared last result")
	private_check(gamma,[alpha,beta],"case 9 gamma")
	await leave(gamma)
	gamma=null
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 9 restarted server shuts down cleanly")

	# 10. Picnic-less world: every showcase action refused with LOCKED, nothing written.
	save_path=folder.path_join("locked.json")
	if not expect(seed_world(save_path,false,{ZETA:{"name":"zeta","at":A_SPOT,"inv":ZETA_BAG}}),"case 10 picnic-less fixture written and accepted by SaveSchema"):return false
	var port3:=start_server()
	expect(port3>0,"case 10 picnic-less server hosts")
	if port3==0:return false
	zeta=await join("zeta",ZETA,port3)
	expect(joined(zeta),"case 10 zeta joins the picnic-less world")
	if not joined(zeta):return false
	await settle([zeta])
	expect(zeta.session.snapshot.get("picnic")==false and zeta.own().get("unlocked")==false and zeta.own().get("can_start")==false,"case 10 zeta's snapshot: picnic=false, own_showcase locked")
	await refuse(zeta,"showcase_start",S,"0",SHOW.LOCKED,"case 10 start before the picnic",[])
	await refuse(zeta,"showcase_join",S,"0",SHOW.LOCKED,"case 10 join before the picnic",[])
	await refuse(zeta,"showcase_leave",S,"",SHOW.LOCKED,"case 10 leave before the picnic",[])
	await refuse(zeta,"showcase_place",A_TILE_1,"0|lantern",SHOW.LOCKED,"case 10 place before the picnic",[])
	await refuse(zeta,"showcase_remove",A_TILE_1,"0",SHOW.LOCKED,"case 10 remove before the picnic",[])
	await refuse(zeta,"showcase_finish",S,"0",SHOW.LOCKED,"case 10 finish before the picnic",[])
	expect(canon(zeta.bag())==canon(ZETA_BAG),"case 10 zeta keeps the exact preset bag")
	await leave(zeta)
	zeta=null
	expect(await stop_server(),"case 10 picnic-less server shuts down with a final save")
	var locked=read_disk()
	expect(locked is Dictionary and not locked.has("showcase") and locked.players.has(ZETA) and not locked.players[ZETA].has("showcase"),"case 10 picnic-less save writes no showcase field")
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
