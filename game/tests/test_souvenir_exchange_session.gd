extends SceneTree
## T071 紀念票兌換裝飾 two-client Session acceptance over a real dedicated server and
## real WebSocket clients.
##
## LEVEL: one machine, ONE Godot process. Inside the single SceneTree a real dedicated
## server Session listens on a free 127.0.0.1 port with the WebSocket transport; separate
## client Session nodes join it over loopback, each in its own branch with its own
## SceneMultiplayer, so every request, notice and snapshot travels the RPC + WebSocket
## path. Clients only read their own received snapshots (data.own_souvenir and the
## players entries; other players' bags are stripped by Session). The server World is
## never touched after seeding. The on-disk save is read (file only) after each normal
## shutdown.
##
## SEEDED FIXTURE (disclosed): built offline in a World before the server starts and
## validated with SaveSchema. picnic=true. The tickets are EARNED in that offline World
## through the activities' real World.act start/join and World.step settlement (timed-out
## rounds pay 1 ticket each): alpha+beta play 3 harvest relay, 3 fishing meet and 3
## showcase rounds together, alpha plays 3 more harvest relay rounds alone, so alpha has
## 6/3/3 and beta 3/3/3 (harvest/fish/showcase). After earning, positions are written
## (alpha A_SPOT, beta B_SPOT, both within reach of the booth at 37,25) and the bags are
## set exactly (alpha {wood 5}, beta {stone 3}). No souvenir field is ever preset.
## Late joiner "gamma" uses a fresh token. Second short run (case 9): a separate save
## with picnic=false and islander "zeta" at A_SPOT holding {radish 2}.
## Everything after the seed goes through client Sessions over the network: every
## redemption and refusal, the sequence replay, the build placement, reconnects,
## shutdowns and restarts.
## Replay (case 4): the raw `request_action` RPC re-sent with an already-used sequence
## number (alpha's redemption) but another affordable entry; Session drops it.
## NOT covered: multiple processes, cross-machine, TLS/wss, latency/packet loss, crash
## durability (only normal shutdowns with a final save), the full-bag and wrong-region
## refusals (rule level, test_souvenir_exchange.gd).
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const SOUV=preload("res://scripts/souvenir_exchange.gd")
const Regions=preload("res://scripts/regions.gd")
const KEY:="souvenir-session"
const ALPHA:="souvenir-session-alpha-token"
const BETA:="souvenir-session-beta-token"
const GAMMA:="souvenir-session-gamma-token"
const ZETA:="souvenir-session-zeta-token"
const START_TIME:=2000.0
const HALF:=Vector2(0.5,0.5)
const BOOTH:=Vector2i(37,25)
const A_SPOT:=Vector2(37.5,27.5)
const B_SPOT:=Vector2(36.5,27.5)
const BUILD_TILE:=Vector2i(38,26)
const ALPHA_BAG:={"wood":5}
const BETA_BAG:={"stone":3}
const ZETA_BAG:={"radish":2}
const SIGNS:={"harvest_relay":Vector2i(32,30),"fish_meet":Vector2i(54,38),"showcase":Vector2i(26,45)}
const PREFIXES:={"harvest_relay":"harvest","fish_meet":"fish_meet","showcase":"showcase"}

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
		var v=session.snapshot.get("own_souvenir",null)
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
	create_timer(170.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("SOUVENIR_SESSION watchdog fired before completion")
	print("SOUVENIR_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("SOUVENIR_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("SOUVENIR_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("SOUVENIR_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

## Real rounds in the offline seeding World: every participant earns 1 ticket per round.
func earn(w:World,activity:String,tokens:Array,rounds:int)->bool:
	var sign:Vector2i=SIGNS[activity]
	var prefix:String=PREFIXES[activity]
	for r in rounds:
		var current:Variant=w.state.get(activity)
		var round_id:=int(current.get("round",0)) if current is Dictionary else 0
		if current is Dictionary:w.state.time=maxf(float(w.state.time),float(current.get("ready",0.0)))+1.0
		for token:String in tokens:
			w.state.players[token].x=float(sign.x)+0.5
			w.state.players[token].y=float(sign.y)+1.5
		serial+=1
		if not w.act(str(tokens[0]),"seed-%d"%serial,prefix+"_start",sign,str(round_id)).ok:return false
		for i in range(1,tokens.size()):
			serial+=1
			if not w.act(str(tokens[i]),"seed-%d"%serial,prefix+"_join",sign,str(round_id+1)).ok:return false
		w.state.time=float(w.state[activity].ends)+0.25
		w.step(0.5,true)
		if w.state[activity].active!=false:return false
	return true

func seed_world(path:String,picnic:bool,people:Dictionary,earned:bool)->bool:
	var w:=World.new()
	w.state["picnic"]=picnic
	w.state["time"]=START_TIME
	for token:String in people:w.add_player(token,str(people[token].name))
	if earned:
		if not earn(w,"harvest_relay",[ALPHA,BETA],3):return false
		if not earn(w,"harvest_relay",[ALPHA],3):return false
		if not earn(w,"fish_meet",[ALPHA,BETA],3):return false
		if not earn(w,"showcase",[ALPHA,BETA],3):return false
	for token:String in people:
		var spec:Dictionary=people[token]
		var p:Dictionary=w.state.players[token]
		var at:Vector2=spec.at
		p["x"]=at.x
		p["y"]=at.y
		p["inventory"]=(spec.inv as Dictionary).duplicate()
		p.erase("receipts")
		p["receipts"]={}
	w.active_tokens.clear()
	w.save_path=path
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:return false
	for token:String in people:
		if parsed.players.get(token,{}).has("souvenir"):return false
	return Schema.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

static func tickets_on(state:Dictionary,token:String)->Dictionary:
	var out:={}
	for activity:String in SOUV.ACTIVITIES:
		var r=state.players.get(token,{}).get(activity,{})
		out[activity]=int(r.get("tickets",0)) if r is Dictionary else 0
	return out

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
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty() and not c.own().is_empty()

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

static func public_id(token:String)->String:
	return token.sha256_text().left(16)

static func ints(d:Variant)->Dictionary:
	var out:={}
	if not d is Dictionary:return {"<invalid>":true}
	for k in d:out[str(k)]=int(d[k])
	return out

## Received own_souvenir normalised.
static func mrow(v:Dictionary)->Dictionary:
	if v.is_empty():return {"<missing>":true}
	var entries:={}
	for e in v.get("entries",[]):
		entries[str(e.get("id",""))]={"redeemed":int(e.get("redeemed",-1)),"held":int(e.get("held",-1)),"placed":int(e.get("placed",-1)),"affordable":e.get("affordable"),"extra":str(e.get("extra",""))}
	return {"unlocked":v.get("unlocked"),"available":v.get("available"),"point":str(v.get("point")),"earned":ints(v.get("earned")),"spent":ints(v.get("spent")),
		"balance":ints(v.get("balance")),"redeemed_total":int(v.get("redeemed_total",-1)),"entries":entries}

func expect_balance(c:Client,earned:Dictionary,spent:Dictionary,label:String)->bool:
	var bal:={}
	for activity:String in SOUV.ACTIVITIES:bal[activity]=int(earned[activity])-int(spent[activity])
	var v:=mrow(c.own())
	return expect(text(v.earned)==text(earned) and text(v.spent)==text(spent) and text(v.balance)==text(bal),
		"%s: %s's own_souvenir earned %s spent %s balance %s (got %s / %s / %s)"%[label,c.label,text(earned),text(spent),text(bal),text(v.earned),text(v.spent),text(v.balance)])

## Everything a client sees about the bags/progress of itself and the other client.
func marks_of(clients:Array)->Array:
	return clients.map(func(x):
		var row:=[text(canon(x.bag())),x.coins(),text(mrow(x.own()))]
		var people=x.session.snapshot.get("players",{})
		if people is Dictionary:
			var ids:Array=people.keys()
			ids.sort()
			for id in ids:row.append(text(canon(people[id].get("inventory",{}))))
		var objects=x.session.snapshot.get("objects",{})
		row.append(text(objects.keys() if objects is Dictionary else []))
		return row)

## Exact refusal; bags, coins, own views and objects unchanged on every end.
func refuse(c:Client,action:String,p:Vector2i,extra:String,message:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var marks:=marks_of(everyone)
	var r:=await act(c,action,p,extra)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	expect(marks_of(everyone)==marks,"%s: every bag, purse, own_souvenir and object list unchanged in all watching snapshots"%label)

func succeed(c:Client,action:String,p:Vector2i,extra:String,label:String,watchers:Array)->Dictionary:
	var r:=await act(c,action,p,extra)
	expect(r.replied and r.ok,"%s: ok (got ok=%s '%s')"%[label,str(r.ok),str(r.message)])
	await settle([c]+watchers)
	return r

## Privacy of `c`'s received snapshot.
func private_check(c:Client,others:Array,label:String)->void:
	var people=c.session.snapshot.get("players",{})
	var clean:=people is Dictionary
	if clean:
		for id in people:
			var person=people[id]
			if not person is Dictionary or person.has("souvenir") or person.has("own_souvenir"):clean=false
			elif id!=c.session.own_id and person.has("inventory"):clean=false
	expect(clean,"%s: no players entry in %s's snapshot carries a souvenir record or another player's bag"%[label,c.label])
	var dump:=JSON.stringify(c.session.snapshot)
	expect(dump.count("\"own_souvenir\"")==1,"%s: %s's snapshot carries exactly one own_souvenir"%[label,c.label])
	var leaked:=false
	for o:Client in others+[c]:
		if dump.contains(o.token):leaked=true
	expect(not leaked,"%s: %s's snapshot contains no private token"%[label,c.label])

static func disk_record(person:Variant)->Variant:
	if not person is Dictionary or not person.has("souvenir"):return null
	var r=person.souvenir
	if not r is Dictionary:return "<invalid>"
	return {"spent":ints(r.get("spent")),"redeemed":ints(r.get("redeemed")),"size":r.size()}

static func want_record(spent:Dictionary,redeemed:Dictionary)->Dictionary:
	return {"spent":spent,"redeemed":redeemed,"size":2}

func read_disk()->Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(save_path))

# --------------------------------------------------------------- scenario --

var alpha:Client
var beta:Client
var gamma:Client
var zeta:Client

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("souvenir-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	save_path=folder.path_join("world.json")
	var seeded:=seed_world(save_path,true,{ALPHA:{"name":"alpha","at":A_SPOT,"inv":ALPHA_BAG},BETA:{"name":"beta","at":B_SPOT,"inv":BETA_BAG}},true)
	if not expect(seeded,"SEEDED FIXTURE (picnic, tickets EARNED in real offline rounds, positions, bags; no souvenir field) written to TEMP and accepted by SaveSchema.validate"):return false
	var seed_disk=read_disk()
	var earned_a:=tickets_on(seed_disk,ALPHA)
	var earned_b:=tickets_on(seed_disk,BETA)
	expect(text(earned_a)==text({"harvest_relay":6,"fish_meet":3,"showcase":3}) and text(earned_b)==text({"harvest_relay":3,"fish_meet":3,"showcase":3}),"seed: alpha earned 6/3/3, beta 3/3/3 in real rounds (%s / %s)"%[text(earned_a),text(earned_b)])
	var probe:=World.new()
	if not expect(probe.load_world(save_path),"probe: the seeded save loads like the server's"):return false
	expect(SOUV.active_cell(probe.state)==BOOTH,"probe: booth at 37,25")
	for spot:Vector2 in [A_SPOT,B_SPOT]:expect(probe.can_stand(spot) and spot.distance_to(Vector2(BOOTH)+HALF)<=SOUV.REACH,"probe: %s standable and within reach"%str(spot))
	expect(A_SPOT.distance_to(Vector2(BUILD_TILE)+HALF)<=3.2 and probe.resource(BUILD_TILE)=="" and not probe.protected(BUILD_TILE) and not probe.state.objects.has(World.key(BUILD_TILE)),"probe: build tile 38,26 is free and in reach of alpha")
	probe=null
	var zero:={"harvest_relay":0,"fish_meet":0,"showcase":0}
	var port:=start_server()
	expect(port>0,"server Session hosts on 127.0.0.1 with the websocket transport")
	if port==0:return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback and received own_souvenir")
	if not joined(alpha) or not joined(beta):return false
	var ws:bool=server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and beta.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer
	expect(ws,"server and both clients use WebSocketMultiplayerPeer")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World (snapshots only)")
	await settle([alpha,beta])
	print("SOUVENIR_SESSION_LABEL machine=single process=single transport=%s loopback=127.0.0.1:%d clients=2(+late joiner,+picnic-less run) fixture=SEEDED(picnic,tickets earned in offline real rounds,positions,bags) shutdown=normal-only(not crash durability)"%["websocket" if ws else "UNEXPECTED",port])
	var ida:=public_id(ALPHA)

	# 1. Fresh private views.
	for c:Client in [alpha,beta]:
		var other:Client=beta if c==alpha else alpha
		var v:=c.own()
		expect(c.region()==Regions.HOME and v.get("unlocked")==true and v.get("available")==true and v.get("can_redeem")==true and v.get("point")==BOOTH,"case 1 %s: booth open at 37,25 in its own view"%c.label)
		expect((v.get("entries",[]) as Array).size()==7 and int(v.get("redeemed_total",-1))==0,"case 1 %s: seven entries, nothing redeemed"%c.label)
		expect(World.souvenir_cell(c.session.snapshot)==BOOTH,"case 1 %s: booth cell computable from its home snapshot"%c.label)
		private_check(c,[other],"case 1")
	expect_balance(alpha,earned_a,zero,"case 1")
	expect_balance(beta,earned_b,zero,"case 1")
	expect(canon(alpha.bag())==canon(ALPHA_BAG) and canon(beta.bag())==canon(BETA_BAG),"preset bags arrive unchanged in the own snapshots")
	var coins_a0:=alpha.coins()
	var coins_b0:=beta.coins()

	# 2. Refusals over the network: both ends unchanged.
	await refuse(alpha,"souvenir_redeem",Vector2i(35,26),"veg_basket_rack|0",SOUV.WRONG_POINT,"case 2 alpha at the wrong point",[beta])
	await refuse(alpha,"souvenir_redeem",BOOTH,"veg_basket_rack|1",SOUV.STALE,"case 2 alpha with a stale count",[beta])
	await refuse(alpha,"souvenir_redeem",BOOTH,"bonfire|0",SOUV.UNKNOWN_ENTRY,"case 2 alpha redeems an unknown entry",[beta])
	await refuse(alpha,"souvenir_redeem",BOOTH,"flower_arch|0",SOUV.NOT_ENOUGH%"家園布置題的紀念票 3 張","case 2 alpha short on showcase tickets",[beta])
	await refuse(beta,"souvenir_redeem",BOOTH,"relay_crate_stack|0",SOUV.NOT_ENOUGH%"豐收接力的紀念票 3 張","case 2 beta short on harvest tickets",[alpha])
	await refuse(beta,"build",BOOTH,"lamp","這裡是水域或公共通道，請換個位置","case 2 beta builds on the booth tile",[alpha])

	# 3. Alpha redeems; only alpha's view and bag change.
	var beta_view:=text(mrow(beta.own()))
	var first:=await succeed(alpha,"souvenir_redeem",BOOTH,"relay_crate_stack|0","case 3 alpha redeems relay_crate_stack (6 harvest tickets)",[beta])
	expect(str(first.message).contains("接力菜箱堆"),"case 3 message names the decor (%s)"%str(first.message))
	await settle([alpha,beta])
	expect_balance(alpha,earned_a,{"harvest_relay":6,"fish_meet":0,"showcase":0},"case 3")
	expect(canon(alpha.bag())==canon({"wood":5,"relay_crate_stack_kit":1}) and alpha.coins()==coins_a0,"case 3 alpha's own bag gains exactly one kit; purse unchanged")
	expect(text(mrow(beta.own()))==beta_view,"case 3 beta's own_souvenir unchanged by alpha's redemption")
	expect(not beta.other(ida).has("inventory") and not beta.other(ida).has("souvenir"),"case 3 beta's snapshot of alpha carries no bag or souvenir record")
	await refuse(alpha,"souvenir_redeem",BOOTH,"relay_crate_stack|0",SOUV.STALE,"case 3 alpha repeats the same request with a new sequence",[beta])

	# 4. Replay: alpha's used sequence re-sent with another affordable entry; dropped.
	var counts:=[alpha.notices.size(),beta.notices.size()]
	var before4:=marks_of([alpha,beta])
	alpha.session.request_action.rpc_id(1,int(first.sequence),"souvenir_redeem",BOOTH,"carp_banner|0",alpha.region(),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==counts[0] and beta.notices.size()==counts[1],"case 4 re-sent redemption (same sequence %d) gets no notice"%int(first.sequence))
	expect(marks_of([alpha,beta])==before4 and int(alpha.own().get("redeemed_total",-1))==1,"case 4 re-sent redemption changes nothing on either end")

	# 5. Beta redeems the mixed entry.
	await succeed(beta,"souvenir_redeem",BOOTH,"trio_keepsake|0","case 5 beta redeems trio_keepsake (3+3+3)",[alpha])
	await settle([alpha,beta])
	expect_balance(beta,earned_b,{"harvest_relay":3,"fish_meet":3,"showcase":3},"case 5")
	expect(canon(beta.bag())==canon({"stone":3,"trio_keepsake_kit":1}) and beta.coins()==coins_b0,"case 5 beta's bag gains the kit; purse unchanged")
	expect_balance(alpha,earned_a,{"harvest_relay":6,"fish_meet":0,"showcase":0},"case 5 alpha unaffected")
	await refuse(beta,"souvenir_redeem",BOOTH,"trio_keepsake|1",SOUV.NOT_ENOUGH%"豐收接力的紀念票 3 張、河岸釣魚會的紀念票 3 張、家園布置題的紀念票 3 張","case 5 beta tries the trio again",[alpha])

	# 6. Alpha places the decor through the normal build action; both ends see it.
	await succeed(alpha,"build",BUILD_TILE,"relay_crate_stack","case 6 alpha places the relay crate stack",[beta])
	await settle([alpha,beta])
	var key:=World.key(BUILD_TILE)
	for c:Client in [alpha,beta]:
		var obj=c.session.snapshot.get("objects",{}).get(key,{})
		expect(obj is Dictionary and str(obj.get("type",""))=="relay_crate_stack" and str(obj.get("owner",""))==ida,"case 6 %s sees the placed decor owned by alpha's public id"%c.label)
	expect(canon(alpha.bag())==canon(ALPHA_BAG),"case 6 placing consumed the kit")
	var e:Dictionary={}
	for row in alpha.own().get("entries",[]):
		if row.id=="relay_crate_stack":e=row
	expect(int(e.get("placed",-1))==1 and int(e.get("held",-1))==0 and int(e.get("redeemed",-1))==1,"case 6 alpha's view: placed 1, held 0, redeemed 1")
	await settle([alpha,beta])
	var marks6:=marks_of([alpha,beta])
	var steal:=await act(beta,"remove",BUILD_TILE,"")
	expect(steal.replied and not steal.ok and not str(steal.message).is_empty(),"case 6 beta cannot pick up alpha's decor (%s)"%str(steal.message))
	await settle([alpha,beta])
	expect(marks_of([alpha,beta])==marks6,"case 6 beta's refused removal changes nothing on either end")
	private_check(alpha,[beta],"case 6 alpha")
	private_check(beta,[alpha],"case 6 beta")

	# 7. Normal shutdown, exact save, restart, late joiner.
	await settle([alpha,beta])
	var final_own:={ALPHA:text(mrow(alpha.own())),BETA:text(mrow(beta.own()))}
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 7 server Session shuts down with a final save")
	var disk=read_disk()
	expect(disk is Dictionary,"case 7 save file parses")
	if not disk is Dictionary:return false
	expect(Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"case 7 saved world passes SaveSchema")
	expect(text(disk_record(disk.players.get(ALPHA,{})))==text(want_record({"fish_meet":0,"harvest_relay":6,"showcase":0},{"relay_crate_stack":1})),"case 7 save holds alpha's exact record (got %s)"%text(disk_record(disk.players.get(ALPHA,{}))))
	expect(text(disk_record(disk.players.get(BETA,{})))==text(want_record({"fish_meet":3,"harvest_relay":3,"showcase":3},{"trio_keepsake":1})),"case 7 save holds beta's exact record (got %s)"%text(disk_record(disk.players.get(BETA,{}))))
	expect(text(tickets_on(disk,ALPHA))==text(earned_a) and text(tickets_on(disk,BETA))==text(earned_b),"case 7 save: the activities' earned ticket counters are unchanged")
	for activity:String in SOUV.ACTIVITIES:
		expect(text(disk.players[ALPHA].get(activity))==text(seed_disk.players[ALPHA].get(activity)) and text(disk.players[BETA].get(activity))==text(seed_disk.players[BETA].get(activity)),"case 7 save: %s records identical to the seed"%activity)
	expect(canon(disk.players[ALPHA].get("inventory",{}))==canon(ALPHA_BAG) and canon(disk.players[BETA].get("inventory",{}))==canon({"stone":3,"trio_keepsake_kit":1}),"case 7 save holds both exact bags")
	expect(int(disk.players[ALPHA].get("coins",-1))==coins_a0 and int(disk.players[BETA].get("coins",-1))==coins_b0,"case 7 save holds both purses")
	var placed=disk.objects.get(key,{})
	expect(placed is Dictionary and str(placed.get("type",""))=="relay_crate_stack" and str(placed.get("owner",""))==ALPHA,"case 7 save holds the placed decor with alpha as owner")
	expect(not disk.objects.has(World.key(BOOTH)),"case 7 save: nothing built on the booth tile")
	var port2:=start_server()
	expect(port2>0,"case 7 a new server Session hosts the same save")
	if port2==0:return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	expect(joined(alpha) and joined(beta),"case 7 both clients rejoin the restarted server")
	if not joined(alpha) or not joined(beta):return false
	await settle([alpha,beta])
	expect(text(mrow(alpha.own()))==final_own[ALPHA],"case 7 alpha's own_souvenir identical after restart (%s)"%text(mrow(alpha.own())))
	expect(text(mrow(beta.own()))==final_own[BETA],"case 7 beta's own_souvenir identical after restart (%s)"%text(mrow(beta.own())))
	gamma=await join("gamma",GAMMA,port2)
	expect(joined(gamma),"case 7 late joiner gamma joins with a fresh token")
	if not joined(gamma):return false
	await settle([alpha,beta,gamma])
	expect_balance(gamma,zero,zero,"case 7 late joiner")
	expect(int(gamma.own().get("redeemed_total",-1))==0 and gamma.own().get("can_redeem")==true,"case 7 late joiner: empty record, booth open")
	private_check(gamma,[alpha,beta],"case 7 gamma")
	await refuse(gamma,"souvenir_redeem",BOOTH,"veg_basket_rack|0",SOUV.TOO_FAR,"case 7 gamma redeems from the spawn",[alpha,beta])
	await leave(gamma)
	gamma=null
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 7 restarted server shuts down cleanly")
	var after_restart=read_disk()
	expect(after_restart is Dictionary and after_restart.players.has(GAMMA) and not after_restart.players[GAMMA].has("souvenir"),"case 7 late joiner's save record has no souvenir field")

	# 8/9. Picnic-less world: redemption refused with LOCKED, nothing written.
	save_path=folder.path_join("locked.json")
	if not expect(seed_world(save_path,false,{ZETA:{"name":"zeta","at":A_SPOT,"inv":ZETA_BAG}},false),"case 9 picnic-less fixture written and accepted by SaveSchema"):return false
	var port3:=start_server()
	expect(port3>0,"case 9 picnic-less server hosts")
	if port3==0:return false
	zeta=await join("zeta",ZETA,port3)
	expect(joined(zeta),"case 9 zeta joins the picnic-less world")
	if not joined(zeta):return false
	await settle([zeta])
	expect(zeta.session.snapshot.get("picnic")==false and zeta.own().get("unlocked")==false and zeta.own().get("can_redeem")==false,"case 9 zeta's snapshot: picnic=false, own_souvenir locked")
	for entry:String in SOUV.ENTRY_ORDER:
		await refuse(zeta,"souvenir_redeem",BOOTH,entry+"|0",SOUV.LOCKED,"case 9 %s before the picnic"%entry,[])
	expect(canon(zeta.bag())==canon(ZETA_BAG),"case 9 zeta keeps the exact preset bag")
	await leave(zeta)
	zeta=null
	expect(await stop_server(),"case 9 picnic-less server shuts down with a final save")
	var locked=read_disk()
	expect(locked is Dictionary and locked.players.has(ZETA) and not locked.players[ZETA].has("souvenir"),"case 9 picnic-less save writes no souvenir field")
	if locked is Dictionary:
		expect(canon(locked.players.get(ZETA,{}).get("inventory",{}))==canon(ZETA_BAG),"case 9 picnic-less save keeps zeta's exact bag")
	return true

func teardown()->void:
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
