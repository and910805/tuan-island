extends SceneTree
## 第 40 章「茶陶上桌」two-client Session acceptance over a real dedicated server and real
## WebSocket clients (modelled on test_table_warmer_session.gd).
##
## LEVEL: one machine, ONE Godot process. A dedicated server Session listens on a free
## 127.0.0.1 port (websocket transport); two client Sessions (alpha, beta) and later a late
## joiner (gamma) join over loopback, each in its own branch with its own SceneMultiplayer.
## Clients only read their own received snapshots. The server World is never touched after
## seeding; the on-disk save is read (file only) after shutdowns.
##
## SEEDED FIXTURE (disclosed): built offline in a World before the server starts and
## validated with SaveSchema. EARNED there through World.act: the picnic ("picnic", so the
## shared table sits at 39,30), alpha's whole tea comparison (tea_intro … tea_discuss + one
## deep roast, timers through World.step), the island-wide 貓空與鶯歌回訪 (6 jars, 6 fills,
## send) and alpha's tea_ware_kit claim. WRITTEN DIRECTLY: chapter_one.shipped/watered,
## board=true, soup 2 / bread 1, player region/x/y and travel_book.visited during the tea
## chain, alpha's five extra worn jars and the roasted tea for the order beyond her earned
## deep roast, final positions (alpha 40.5,30.5; beta 38.5,30.5), beta's tea_ware_kit 1 and
## tea_light 1, emptied receipts. No tea_service key is ever preset.
## Everything after the seed goes through client Sessions over the network.
## Replay: the raw request_action RPC re-sent with an already-used sequence number (alpha's
## place sequence carrying a sip, and alpha's sip sequence again); Session drops both.
## Brew day: rounds carry round.day (world day). The server clock runs 1:1 from the seeded
## time (~100 s into day 1) and the run is capped at 120 s, so every brew lands on the seeded
## day (asserted at seed time); the expected day is TS.today(seeded save), not hard-coded.
## NOT covered: multiple processes, TLS, latency/loss, crash durability (normal shutdowns
## only), wrong-region / too-far / BAG_FULL refusals and the cold (next-day) rule (rule
## level, test_tea_service.gd).
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const TS=preload("res://scripts/tea_service.gd")
const TR=preload("res://scripts/tea_revisit.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const Community=preload("res://scripts/community.gd")
const KEY:="tea-service-session"
const ALPHA:="teaservice-session-alpha-token"
const BETA:="teaservice-session-beta-token"
const GAMMA:="teaservice-session-gamma-token"
const KIT:="tea_ware_kit"
const TABLE:=Vector2i(39,30)
const BOARD:=Vector2i(40,29)
const A_SPOT:=Vector2(40.5,30.5)
const B_SPOT:=Vector2(38.5,30.5)
const AT_POTTER:=Vector2(20.5,21.5)
const AT_PACKER:=Vector2(26.5,21.5)

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
	func tea()->Variant:
		return session.snapshot.get("tea_service",null)

var checks:=0
var failures:=0
var serial:=0
var seed_serial:=0
var folder:=""
var save_path:=""
var server
var server_branch:Node
var finished:=false
var alpha:Client
var beta:Client
var gamma:Client
var alpha_bag0:={}
var beta_bag0:={}
var brew_day:=-1

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)
	return ok

func _initialize()->void:
	create_timer(120.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("TEA_SERVICE_SESSION watchdog fired before completion")
	print("TEA_SERVICE_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("TEA_SERVICE_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("TEA_SERVICE_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("TEA_SERVICE_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

func put(w:World,token:String,at:Vector2,region:String) -> void:
	var p:Dictionary=w.state.players[token]
	p["region"]=region
	p["x"]=at.x
	p["y"]=at.y
	if region in World.TRANSIT.ROUTE:p.travel_book.visited[region]=true

func seed_act(w:World,token:String,action:String,p:Vector2i,extra:String="")->bool:
	seed_serial+=1
	var r:Dictionary=w.act(token,"seed-%d"%seed_serial,action,p,extra)
	if not bool(r.get("ok",false)):push_error("seed step %s failed: %s"%[action,str(r.get("message",""))])
	return bool(r.get("ok",false))

func tea_step(w:World,token:String,action:String,region:String,cell:Vector2i,extra:String="")->bool:
	put(w,token,Vector2(cell)+Vector2(0.5,1.5),region)
	return seed_act(w,token,action,cell,extra)

func give(w:World,token:String,item:String,count:int)->void:
	var bag:Dictionary=w.state.players[token].inventory
	bag[item]=int(bag.get(item,0))+count

## Earned two-packaging comparison (same chain as test_tea_revisit.gd).
func earn_comparison(w:World,token:String)->bool:
	if not tea_step(w,token,"tea_intro","home",Tea.RECEIVER):return false
	if not tea_step(w,token,"tea_potter",Tea.YINGGE,Tea.POTTER):return false
	if not tea_step(w,token,"tea_fire",Tea.YINGGE,Tea.KILN) or not w.step(Tea.KILN_SECONDS,true):return false
	if not tea_step(w,token,"tea_fire_take",Tea.YINGGE,Tea.KILN):return false
	if not tea_step(w,token,"tea_pick",Tea.MAOKONG,Tea.TEA_NODES[0]) or not tea_step(w,token,"tea_roast",Tea.MAOKONG,Tea.ROASTER,"light"):return false
	if not w.step(Tea.ROAST_SECONDS.light,true) or not tea_step(w,token,"tea_take",Tea.MAOKONG,Tea.ROASTER):return false
	if not tea_step(w,token,"tea_pack",Tea.MAOKONG,Tea.PACKER,"light:jar") or not tea_step(w,token,"tea_ship",Tea.MAOKONG,Tea.PACKER):return false
	if not w.step(Tea.SHIPPING_SECONDS,true) or not tea_step(w,token,"tea_sell","home",Tea.RECEIVER) or not tea_step(w,token,"tea_return","home",Tea.RECEIVER):return false
	if not w.step(Tea.RETURN_SECONDS,true) or not tea_step(w,token,"tea_reclaim",Tea.MAOKONG,Tea.PACKER):return false
	if not tea_step(w,token,"tea_pick",Tea.MAOKONG,Tea.TEA_NODES[1]) or not tea_step(w,token,"tea_roast",Tea.MAOKONG,Tea.ROASTER,"light"):return false
	if not w.step(Tea.ROAST_SECONDS.light,true) or not tea_step(w,token,"tea_take",Tea.MAOKONG,Tea.ROASTER):return false
	if not tea_step(w,token,"tea_pack",Tea.MAOKONG,Tea.PACKER,"light:fiber") or not tea_step(w,token,"tea_ship",Tea.MAOKONG,Tea.PACKER):return false
	if not w.step(Tea.SHIPPING_SECONDS,true) or not tea_step(w,token,"tea_sell","home",Tea.RECEIVER):return false
	if not tea_step(w,token,"tea_discuss",Tea.MAOKONG,Tea.TEA_NPC):return false
	if not tea_step(w,token,"tea_pick",Tea.MAOKONG,Tea.TEA_NODES[2]) or not tea_step(w,token,"tea_roast",Tea.MAOKONG,Tea.ROASTER,"deep"):return false
	if not w.step(Tea.ROAST_SECONDS.deep,true) or not tea_step(w,token,"tea_take",Tea.MAOKONG,Tea.ROASTER):return false
	return Tea.own_record(w.state,token).comparison_complete==true

func complete_revisit(w:World)->bool:
	give(w,ALPHA,"tea_worn_jar",5)
	put(w,ALPHA,AT_POTTER,"yingge")
	if not seed_act(w,ALPHA,TR.JAR_ACTION,TR.POTTER,"tea_returned_jar"):return false
	for i in 5:
		if not seed_act(w,ALPHA,TR.JAR_ACTION,TR.POTTER,"tea_worn_jar"):return false
	var need:Dictionary=TR.order(w.state)
	for style:String in TR.STYLES:
		var item:String=TR.TEA_ITEMS[style]
		var have:=int(w.state.players[ALPHA].inventory.get(item,0))
		if have<int(need[style]):give(w,ALPHA,item,int(need[style])-have)
	put(w,ALPHA,AT_PACKER,"maokong")
	for style:String in TR.STYLES:
		for k in int(need[style]):
			if not seed_act(w,ALPHA,TR.FILL_ACTION,TR.PACKER,style):return false
	if not seed_act(w,ALPHA,TR.SEND_ACTION,TR.PACKER,""):return false
	put(w,ALPHA,AT_POTTER,"yingge")
	if not seed_act(w,ALPHA,TR.CLAIM_ACTION,TR.POTTER,""):return false
	return TR.completed(w.state) and int(w.state.players[ALPHA].inventory.get(KIT,0))==1

func seed_world(path:String)->bool:
	var w:=World.new()
	w.add_player(ALPHA,"alpha")
	w.add_player(BETA,"beta")
	w.state.chapter_one.shipped=true
	w.state.chapter_one.watered=true
	w.state["board"]=true
	put(w,ALPHA,A_SPOT,"home")
	put(w,BETA,B_SPOT,"home")
	var a:Dictionary=w.state.players[ALPHA]
	a.inventory["soup"]=2
	a.inventory["bread"]=1
	if not seed_act(w,ALPHA,"picnic",BOARD):return false
	if Community.table_cell(w.state)!=TABLE:return false
	if not earn_comparison(w,ALPHA):return false
	if not complete_revisit(w):return false
	put(w,ALPHA,A_SPOT,"home")
	put(w,BETA,B_SPOT,"home")
	a=w.state.players[ALPHA]
	var b:Dictionary=w.state.players[BETA]
	b.inventory[KIT]=1
	b.inventory["tea_light"]=1
	for p:Dictionary in [a,b]:p["receipts"]={}
	w.active_tokens.clear()
	w.save_path=path
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.has("tea_service"):return false
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
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty() and c.session.snapshot.get("community") is Dictionary

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

static func without(bag:Dictionary,item:String)->Dictionary:
	var out:=bag.duplicate()
	out.erase(item)
	return out

static func key_list(d:Variant)->Array:
	var keys:Array=[]
	if not d is Dictionary:return keys
	for k in d:keys.append(str(k))
	keys.sort()
	return keys

## Normalised view of a received tea_service (ints for portions / day, sorted key list).
static func tea_row(t:Variant)->String:
	if not t is Dictionary:return "none"
	var pot:Variant=t.get("round")
	var row:={"keys":key_list(t),"placed":t.get("placed"),"lender_own":t.get("lender_own"),"sipped_own":t.get("sipped_own")}
	if pot is Dictionary:
		var day:Variant=pot.get("day",-1)
		row["round"]={"keys":key_list(pot),"style":str(pot.get("style","")),"portions":int(pot.get("portions",-1)),"day":int(day) if (day is int or day is float) else -1}
	return text(row)

## Expected view: placed, own flags, optional round (brewed on world day `day`).
static func want_row(lender:bool,sipped:bool,style:String="",cups:int=-1,day:int=-1)->String:
	var keys:=["lender_own","placed","sipped_own"]
	var row:={"keys":keys,"placed":true,"lender_own":lender,"sipped_own":sipped}
	if not style.is_empty():
		keys=["lender_own","placed","round","sipped_own"]
		row["keys"]=keys
		row["round"]={"keys":["day","portions","style"],"style":style,"portions":cups,"day":day}
	return text(row)

func marks_of(clients:Array)->Array:
	return clients.map(func(x):return [text(canon(x.bag())),tea_row(x.tea())])

func refuse(c:Client,action:String,p:Vector2i,extra:String,message:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var marks:=marks_of(everyone)
	var r:=await act(c,action,p,extra)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	expect(marks_of(everyone)==marks,"%s: bags and tea_service unchanged in every watching snapshot"%label)

func succeed(c:Client,action:String,p:Vector2i,extra:String,label:String,watchers:Array)->Dictionary:
	var r:=await act(c,action,p,extra)
	expect(r.replied and r.ok,"%s: ok (got ok=%s '%s')"%[label,str(r.ok),str(r.message)])
	await settle([c]+watchers)
	return r

func private_check(c:Client,others:Array,label:String)->void:
	var dump:=JSON.stringify(c.session.snapshot)
	var tea_dump:=JSON.stringify(c.tea())
	var leaked:=false
	var tea_leaked:=false
	for o:Client in others+[c]:
		if dump.contains(o.token):leaked=true
		if tea_dump.contains(o.token):tea_leaked=true
	expect(not tea_leaked,"%s: %s's tea_service carries no token"%[label,c.label])
	expect(not leaked,"%s: %s's snapshot contains no raw token"%[label,c.label])
	var t:Variant=c.tea()
	if t is Dictionary:
		expect(not t.has("lender") and not (t.get("round") is Dictionary and t.round.has("claimed")),"%s: %s's tea_service has no lender / claim map"%[label,c.label])

func read_disk()->Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(save_path))

func disk_valid(disk:Variant)->bool:
	return disk is Dictionary and Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func sorted_keys(d:Variant)->Array:
	return key_list(d)

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("tea-service-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"SEEDED FIXTURE (picnic, comparison, revisit and alpha's kit earned offline; beta's kit/tea and positions written; no tea_service) accepted by SaveSchema"):return false
	var seeded=read_disk()
	if not expect(seeded is Dictionary,"seeded save parses"):return false
	alpha_bag0=canon(seeded.players[ALPHA].inventory)
	beta_bag0=canon(seeded.players[BETA].inventory)
	expect(int(alpha_bag0.get(KIT,0))==1 and int(beta_bag0.get(KIT,0))==1 and int(beta_bag0.get("tea_light",0))==1,"seed: alpha holds her earned kit, beta a kit and a light roast")
	# The server clock runs 1:1 from the seeded time; the seed ends well before the first
	# midnight and the whole run is capped at 120 s, so every brew lands on the seeded day.
	brew_day=TS.today(seeded)
	var day_left:float=float(brew_day)*World.WEATHER.DAY_SECONDS-float(seeded.get("time",0.0))
	expect(brew_day>=1 and day_left>200.0,"seed: world day %d with %.0f s to midnight (no day change during the run)"%[brew_day,day_left])
	var probe:=World.new()
	if not expect(probe.load_world(save_path),"probe: seeded save loads"):return false
	for spot:Vector2 in [A_SPOT,B_SPOT]:expect(probe.can_stand(spot) and spot.distance_to(Vector2(TABLE)+Vector2(0.5,0.5))<=TS.REACH,"probe: %s standable and within reach of the table"%str(spot))
	probe=null
	var port:=start_server()
	if not expect(port>0,"server Session hosts on 127.0.0.1 (websocket)"):return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	if not expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback"):return false
	var ws:bool=server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer
	expect(ws,"server and clients use WebSocketMultiplayerPeer")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World")
	await settle([alpha,beta])
	print("TEA_SERVICE_SESSION_LABEL machine=single process=single transport=websocket loopback=127.0.0.1:%d clients=2(+late joiner) fixture=SEEDED(picnic+comparison+revisit+claim earned offline,positions,beta kit/tea) shutdown=normal-only"%port)

	# 1. Fresh: nothing on the table.
	for c:Client in [alpha,beta]:
		expect(c.tea()==null and not TS.placed(c.session.snapshot),"case 1 %s: no tea_service in the snapshot"%c.label)
		expect(Community.table_cell(c.session.snapshot)==TABLE and TR.completed(c.session.snapshot),"case 1 %s: table cell and completed revisit visible on the client"%c.label)
		expect(TS.place_block(c.session.snapshot,c.bag())=="","case 1 %s: client-side place_block allows placing"%c.label)
		private_check(c,[beta if c==alpha else alpha],"case 1")
	expect(canon(alpha.bag())==alpha_bag0 and canon(beta.bag())==beta_bag0,"case 1 seeded bags arrive unchanged")

	# 2. Refusals before placing: both ends unchanged.
	await refuse(alpha,TS.BREW_ACTION,TABLE,"light",TS.NOT_PLACED,"case 2 brew with nothing on the table",[beta])
	await refuse(alpha,TS.SIP_ACTION,TABLE,"",TS.NOT_PLACED,"case 2 sip with nothing on the table",[beta])
	await refuse(alpha,TS.PLACE_ACTION,Vector2i(40,31),"",TS.WRONG_CELL,"case 2 place at the wrong cell",[beta])
	await refuse(alpha,TS.PLACE_ACTION,TABLE,"now",TS.BAD_EXTRA,"case 2 place with an extra",[beta])

	# 3. Alpha places over the network; beta's second set is refused.
	var placed:=await succeed(alpha,TS.PLACE_ACTION,TABLE,"","case 3 alpha lends her set",[beta])
	expect(str(placed.message)==TS.PLACED_OK,"case 3 place message")
	await wait_until(func():return TS.placed(alpha.session.snapshot) and TS.placed(beta.session.snapshot),3.0)
	expect(tea_row(alpha.tea())==want_row(true,false),"case 3 alpha sees placed, lender_own true (%s)"%tea_row(alpha.tea()))
	expect(tea_row(beta.tea())==want_row(false,false),"case 3 beta sees placed, lender_own false (%s)"%tea_row(beta.tea()))
	expect(canon(alpha.bag())==without(alpha_bag0,KIT),"case 3 alpha paid exactly one kit (bag %s)"%text(canon(alpha.bag())))
	expect(canon(beta.bag())==beta_bag0,"case 3 beta's bag unchanged")
	await refuse(beta,TS.PLACE_ACTION,TABLE,"",TS.ALREADY,"case 3 beta cannot place a second set",[alpha])
	await refuse(alpha,TS.SIP_ACTION,TABLE,"",TS.NO_ROUND,"case 3 sip before anything is brewed",[beta])

	# 4. Beta brews light.
	var brewed:=await succeed(beta,TS.BREW_ACTION,TABLE,"light","case 4 beta brews her light roast",[alpha])
	expect(str(brewed.message)==TS.BREWED_OK%"淺焙茶","case 4 brew message")
	await wait_until(func():return TS.portions(alpha.session.snapshot)==6 and TS.portions(beta.session.snapshot)==6,3.0)
	expect(tea_row(alpha.tea())==want_row(true,false,"light",6,brew_day),"case 4 alpha sees a 6-cup light round brewed on day %d (%s)"%[brew_day,tea_row(alpha.tea())])
	expect(tea_row(beta.tea())==want_row(false,false,"light",6,brew_day),"case 4 beta sees a 6-cup light round brewed on day %d (%s)"%[brew_day,tea_row(beta.tea())])
	expect(canon(beta.bag())==without(beta_bag0,"tea_light") and canon(alpha.bag())==without(alpha_bag0,KIT),"case 4 beta's light roast left her bag, nothing else changed")
	await refuse(beta,TS.BREW_ACTION,TABLE,"light",TS.TEA_LEFT_BREW,"case 4 brew while cups remain",[alpha])

	# 5. Replay: alpha's used place sequence re-sent as a sip is dropped.
	await settle([alpha,beta])
	var counts:=[alpha.notices.size(),beta.notices.size()]
	var before5:=marks_of([alpha,beta])
	alpha.session.request_action.rpc_id(1,int(placed.sequence),TS.SIP_ACTION,TABLE,"",str(alpha.session.snapshot.get("region_id","")),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==counts[0] and beta.notices.size()==counts[1],"case 5 re-sent sequence %d gets no notice"%int(placed.sequence))
	expect(marks_of([alpha,beta])==before5 and TS.portions(alpha.session.snapshot)==6 and not TS.sipped_own(alpha.session.snapshot),"case 5 re-sent sequence changes nothing on either end (no cup poured)")

	# 6. Both sip; both ends see the portions.
	var sip_a:=await succeed(alpha,TS.SIP_ACTION,TABLE,"","case 6 alpha sips",[beta])
	expect(str(sip_a.message)==TS.SIP_OK%["淺焙茶",5],"case 6 alpha's sip message (%s)"%str(sip_a.message))
	await succeed(beta,TS.SIP_ACTION,TABLE,"","case 6 beta sips",[alpha])
	await wait_until(func():return TS.portions(alpha.session.snapshot)==4 and TS.portions(beta.session.snapshot)==4,3.0)
	expect(tea_row(alpha.tea())==want_row(true,true,"light",4,brew_day),"case 6 alpha sees 4 left and her own sip (%s)"%tea_row(alpha.tea()))
	expect(tea_row(beta.tea())==want_row(false,true,"light",4,brew_day),"case 6 beta sees 4 left and her own sip (%s)"%tea_row(beta.tea()))
	var seen:Dictionary=TS.current_round(alpha.session.snapshot)
	expect(str(seen.get("style",""))=="light" and int(seen.get("portions",-1))==4 and int(seen.get("left",-1))==4 and int(seen.get("day",-1))==brew_day and seen.get("cold")==false,"case 6 client-side current_round on alpha's snapshot: same-day, warm, 4 left (%s)"%text(seen))
	expect(canon(alpha.bag())==without(alpha_bag0,KIT) and canon(beta.bag())==without(beta_bag0,"tea_light"),"case 6 sipping gives no item")
	for c:Client in [alpha,beta]:private_check(c,[beta if c==alpha else alpha],"case 6")
	# Same-sequence resend of alpha's sip applies once.
	await settle([alpha,beta])
	var counts6:=[alpha.notices.size(),beta.notices.size()]
	var before6:=marks_of([alpha,beta])
	alpha.session.request_action.rpc_id(1,int(sip_a.sequence),TS.SIP_ACTION,TABLE,"",str(alpha.session.snapshot.get("region_id","")),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==counts6[0] and beta.notices.size()==counts6[1] and marks_of([alpha,beta])==before6,"case 6 resending alpha's sip sequence %d is dropped (applied once)"%int(sip_a.sequence))
	await refuse(beta,TS.SIP_ACTION,TABLE,"",TS.SIPPED,"case 6 beta sips twice",[alpha])

	# 7. Take refusals: beta is not the lender; alpha must wait for the pot to empty.
	await refuse(beta,TS.TAKE_ACTION,TABLE,"",TS.NOT_LENDER,"case 7 beta takes alpha's set",[alpha])
	await refuse(alpha,TS.TAKE_ACTION,TABLE,"",TS.TEA_LEFT,"case 7 alpha takes while tea is left",[beta])
	expect(TS.take_block(beta.session.snapshot,beta.bag())==TS.NOT_LENDER and TS.take_block(alpha.session.snapshot,alpha.bag())==TS.TEA_LEFT and TS.sip_block(beta.session.snapshot)==TS.SIPPED,"case 7 client-side block reasons agree with the server")

	# 8. Normal shutdown → exact save.
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 8 server shuts down with a final save")
	var disk=read_disk()
	if not expect(disk is Dictionary,"case 8 save parses"):return false
	expect(disk_valid(disk),"case 8 saved world passes SaveSchema")
	var rec=disk.get("tea_service")
	if not expect(rec is Dictionary and rec.get("round") is Dictionary,"case 8 save carries tea_service with a round (%s)"%text(rec)):return false
	expect(str(rec.get("lender",""))==ALPHA and sorted_keys(rec)==["lender","round"],"case 8 save: lender alpha, no other keys")
	expect(str(rec.round.get("style",""))=="light" and int(rec.round.get("portions",-1))==4 and sorted_keys(rec.round)==["claimed","day","portions","style"],"case 8 save: light round, 4 left, keys claimed/day/portions/style (%s)"%text(rec.round))
	expect((rec.round.get("day") is int or rec.round.get("day") is float) and int(rec.round.day)==brew_day and brew_day<=TS.today(disk),"case 8 save: round.day == the brew day %d (<= today %d)"%[brew_day,TS.today(disk)])
	var want:=[ALPHA,BETA]
	want.sort()
	expect(sorted_keys(rec.round.get("claimed"))==want,"case 8 save: exactly alpha and beta sipped")
	expect(canon(disk.players[ALPHA].inventory)==without(alpha_bag0,KIT) and canon(disk.players[BETA].inventory)==without(beta_bag0,"tea_light"),"case 8 save: both exact bags")
	expect(str(disk.community.table)=="39,30","case 8 save: the table did not move")

	# 9. Restart; late joiner sees the same state and can sip once.
	var port2:=start_server()
	if not expect(port2>0,"case 9 restarted server hosts the same save"):return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	if not expect(joined(alpha) and joined(beta),"case 9 both rejoin"):return false
	await settle([alpha,beta])
	await wait_until(func():return TS.portions(alpha.session.snapshot)==4 and TS.portions(beta.session.snapshot)==4,3.0)
	expect(tea_row(alpha.tea())==want_row(true,true,"light",4,brew_day),"case 9 alpha: restart consistent (%s)"%tea_row(alpha.tea()))
	expect(tea_row(beta.tea())==want_row(false,true,"light",4,brew_day),"case 9 beta: restart consistent (%s)"%tea_row(beta.tea()))
	gamma=await join("gamma",GAMMA,port2)
	if not expect(joined(gamma),"case 9 late joiner gamma joins"):return false
	await settle([alpha,beta,gamma])
	expect(tea_row(gamma.tea())==want_row(false,false,"light",4,brew_day),"case 9 gamma sees the set and an unsipped 4-cup round (%s)"%tea_row(gamma.tea()))
	private_check(gamma,[alpha,beta],"case 9")
	await refuse(gamma,TS.SIP_ACTION,TABLE,"","再靠近共餐桌一點。","case 9 ferry spawn is out of reach",[alpha,beta])
	if not expect(await preload("res://tests/community_session_walk.gd").from_ferry(self,gamma.session,A_SPOT),"case 9 late joiner walks to the table over WebSocket"):return false
	await refuse(gamma,TS.PLACE_ACTION,TABLE,"",TS.ALREADY,"case 9 gamma cannot place a second set",[alpha,beta])
	await refuse(gamma,TS.TAKE_ACTION,TABLE,"",TS.NOT_LENDER,"case 9 gamma cannot take alpha's set",[alpha,beta])
	await succeed(gamma,TS.SIP_ACTION,TABLE,"","case 9 gamma sips",[alpha,beta])
	await wait_until(func():return TS.portions(alpha.session.snapshot)==3 and TS.portions(beta.session.snapshot)==3 and TS.portions(gamma.session.snapshot)==3,3.0)
	expect(tea_row(gamma.tea())==want_row(false,true,"light",3,brew_day) and tea_row(alpha.tea())==want_row(true,true,"light",3,brew_day) and tea_row(beta.tea())==want_row(false,true,"light",3,brew_day),"case 9 everyone sees 3 left")
	await refuse(gamma,TS.SIP_ACTION,TABLE,"",TS.SIPPED,"case 9 gamma sips twice",[alpha,beta])
	await leave(gamma)
	gamma=null
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 9 restarted server shuts down cleanly")
	var after=read_disk()
	expect(disk_valid(after),"case 9 final save passes SaveSchema")
	if after is Dictionary and after.get("tea_service") is Dictionary and after.tea_service.get("round") is Dictionary:
		var claimers:=[ALPHA,BETA,GAMMA]
		claimers.sort()
		expect(str(after.tea_service.get("lender",""))==ALPHA and int(after.tea_service.round.get("portions",-1))==3 and sorted_keys(after.tea_service.round.get("claimed"))==claimers and after.players.has(GAMMA),"case 9 final save: lender alpha, 3 left, alpha/beta/gamma sipped, gamma recorded")
		expect(sorted_keys(after.tea_service.round)==["claimed","day","portions","style"] and int(after.tea_service.round.get("day",-1))==brew_day,"case 9 final save: round keeps the brew day %d (%s)"%[brew_day,text(after.tea_service.round)])
	else:
		expect(false,"case 9 final save carries the tea round")
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
