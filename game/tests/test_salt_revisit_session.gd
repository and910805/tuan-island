extends SceneTree
## 第 40 章臺南北門回訪「鹽籃批次」two-client Session acceptance over a real dedicated
## server and real WebSocket clients (modelled on test_tea_revisit_session.gd).
##
## LEVEL: one machine, ONE Godot process. A dedicated server Session listens on a free
## 127.0.0.1 port (websocket transport); two client Sessions (alpha at 阿曬, beta at the
## co-op chest, both in 北門) and later a late joiner (gamma, at home) join over loopback,
## each in its own branch with its own SceneMultiplayer. Clients only read their own
## received snapshots. The server World is never touched after seeding; the on-disk save is
## read (file only) after shutdowns.
##
## SEEDED FIXTURE (disclosed): built offline in a World before the server starts and
## validated with SaveSchema. EARNED there through World.act / World.step: both players'
## salt letter at 小栗's stall, the transit trip home → 田尾 → 北門, salt_intro, the three gate
## repairs (alpha donates), and each player's first hand rake on a public pan (3 sea_salt and
## raked 1 each). Written directly: the chapter 1/2/3 story fixture (as test_salt_pan_world),
## the gate materials, alpha's 15 extra sea_salt (18 = six lots), beta's 12 fiber, the standing
## spots (alpha 44.5,18.5 at 阿曬; beta 47.5,24.5 at the co-op chest), receipts cleared. No
## salt_revisit key is preset. World time starts where the offline rakes left it (day 1,
## sunny, spring) and only advances by the server's real-time ticks.
## Everything after the seed goes through client Sessions over the network. Beta walks
## (input_direction) from the co-op chest east, north and west to 阿曬 to claim.
## Replay: the raw request_action RPC re-sent with alpha's already-used stock sequence number;
## Session drops it.
## NOT covered: multiple processes, TLS, latency/loss, crash durability (normal shutdowns
## only), rain and season changes (rule level, test_salt_revisit.gd).
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const SR=preload("res://scripts/salt_revisit.gd")
const Salt=preload("res://scripts/salt_pan.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const Transit=preload("res://scripts/transit.gd")
const KEY:="salt-revisit-session"
const ALPHA:="saltrevisit-session-alpha-token"
const BETA:="saltrevisit-session-beta-token"
const GAMMA:="saltrevisit-session-gamma-token"
const KIT:="salt_basket_kit"
const STALL:=Vector2i(43,29)
const A_SPOT:=SR.WORKER_STAND
const B_SPOT:=SR.CHEST_STAND

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
	func revisit()->Variant:
		return session.snapshot.get("salt_revisit",null)

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
	print("SALT_REVISIT_SESSION watchdog fired before completion")
	print("SALT_REVISIT_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("SALT_REVISIT_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("SALT_REVISIT_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("SALT_REVISIT_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
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
	var a:Dictionary=w.state.players[ALPHA]
	var b:Dictionary=w.state.players[BETA]
	if not arrive(w,ALPHA) or not arrive(w,BETA):return false
	a.inventory["plank"]=18
	a.inventory["resin"]=3
	a.inventory["stone"]=12
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
	if int(a.inventory.get("sea_salt",0))!=3 or int(b.inventory.get("sea_salt",0))!=3:return false
	if not SR.player_ready(w.state,ALPHA) or not SR.player_ready(w.state,BETA):return false
	a.inventory["sea_salt"]=18 # earned 3 + written 15
	b.inventory["fiber"]=12
	place(w,ALPHA,Salt.REGION,A_SPOT)
	place(w,BETA,Salt.REGION,B_SPOT)
	for p:Dictionary in [a,b]:p["receipts"]={}
	w.active_tokens.clear()
	w.save_path=path
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.has(SR.STATE_KEY) or float(parsed.time)>=1000.0:return false
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
		return arrived.call(c.me()),seconds)
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

func marks_of(clients:Array)->Array:
	return clients.map(func(x):return [text(canon(x.bag())),text(x.revisit())])

func refuse(c:Client,action:String,p:Vector2i,extra:String,message:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var marks:=marks_of(everyone)
	var r:=await act(c,action,p,extra)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	expect(marks_of(everyone)==marks,"%s: bags and salt_revisit unchanged in every watching snapshot"%label)

func succeed(c:Client,action:String,p:Vector2i,extra:String,label:String,watchers:Array)->Dictionary:
	var r:=await act(c,action,p,extra)
	expect(r.replied and r.ok,"%s: ok (got ok=%s '%s')"%[label,str(r.ok),str(r.message)])
	await settle([c]+watchers)
	return r

func private_check(c:Client,others:Array,label:String)->void:
	var dump:=JSON.stringify(c.session.snapshot)
	var leaked:=false
	for o:Client in others+[c]:
		if dump.contains(o.token):leaked=true
	expect(not leaked,"%s: %s's snapshot contains no raw token"%[label,c.label])
	var rec=c.revisit()
	expect(rec==null or (rec is Dictionary and not rec.has("claimed")),"%s: %s's snapshot carries no claim set"%[label,c.label])

func public_row(c:Client)->String:
	var rec=c.revisit()
	if not rec is Dictionary:return "null"
	return text({"stocked":rec.get("stocked"),"packed":rec.get("packed"),"rain_packs":rec.get("rain_packs"),"day":rec.get("day"),"completed":rec.get("completed"),"done_day":rec.get("done_day")})

func row(sunny:int,cloudy:int,kitchen:int,pickle:int,rain:int,day:int,completed:bool,done_day:int)->String:
	return text({"stocked":{"sunny":sunny,"cloudy":cloudy},"packed":{"kitchen":kitchen,"pickle":pickle},"rain_packs":rain,"day":day,"completed":completed,"done_day":done_day})

func read_disk()->Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(save_path))

func disk_valid(disk:Variant)->bool:
	return disk is Dictionary and Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func region_of(c:Client)->String:
	return str(c.session.snapshot.get("region_id",""))

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("salt-revisit-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"SEEDED FIXTURE (letters, trips, gates and both hand rakes earned offline; extra salt/fiber/spots written; no salt_revisit) accepted by SaveSchema"):return false
	var probe:=World.new()
	if not expect(probe.load_world(save_path),"probe: seeded save loads"):return false
	probe.switch_region(Salt.REGION)
	var path_ok:=probe.can_stand(A_SPOT) and probe.can_stand(B_SPOT)
	for x in range(47,51):
		if not probe.can_stand(Vector2(float(x)+0.5,24.5)):path_ok=false
	for y in range(18,25):
		if not probe.can_stand(Vector2(50.5,float(y)+0.5)):path_ok=false
	for x in range(45,51):
		if not probe.can_stand(Vector2(float(x)+0.5,18.5)):path_ok=false
	expect(path_ok,"probe: 北門 walk co-op chest → east → north → west to 阿曬 is standable")
	probe.switch_region("home")
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
	print("SALT_REVISIT_SESSION_LABEL machine=single process=single transport=websocket loopback=127.0.0.1:%d clients=2(+late joiner) fixture=SEEDED(letters,trips,gates,hand rakes earned offline; salt,fiber,spots written) shutdown=normal-only"%port)

	# 1. Fresh: both ready, gates repaired, no record, spring order, sunny day 1.
	for c:Client in [alpha,beta]:
		var snap:Dictionary=c.session.snapshot
		expect(c.revisit()==null and SR.unlocked(snap) and SR.player_ready(snap) and not SR.completed(snap),"case 1 %s: unlocked, ready, no record yet"%c.label)
		expect(SR.today(snap)==1 and SR.order_season(snap)=="spring" and SR.order(snap)=={"kitchen":3,"pickle":3} and not SR.rainy_today(snap),"case 1 %s: day 1 dry spring order 3/3"%c.label)
		private_check(c,[beta if c==alpha else alpha],"case 1")
	expect(SR.stock_block(alpha.session.snapshot,alpha.bag())=="" and SR.pack_block(beta.session.snapshot,"kitchen",beta.bag())==SR.NEED_STOCK%[0,0],"case 1 client helpers: alpha can stock, beta must wait for a lot")

	# 2. Refusals leave both ends unchanged.
	await refuse(beta,SR.PACK_ACTION,SR.CHEST,"kitchen",SR.NEED_STOCK%[0,0],"case 2 pack before any lot",[alpha])
	await refuse(beta,SR.PACK_ACTION,SR.CHEST,"salt",SR.BAD_KIND,"case 2 unknown basket kind",[alpha])
	await refuse(alpha,SR.PACK_ACTION,SR.CHEST,"kitchen",SR.TOO_FAR,"case 2 alpha packs from 阿曬's spot",[beta])
	await refuse(beta,SR.STOCK_ACTION,SR.WORKER,"",SR.TOO_FAR,"case 2 beta stocks from the chest",[alpha])
	await refuse(beta,SR.SEND_ACTION,SR.STOP,"",SR.NOT_PACKED%0,"case 2 send an empty batch",[alpha])
	await refuse(alpha,SR.CLAIM_ACTION,SR.WORKER,"",SR.NOT_DONE,"case 2 claim before completion",[beta])

	# 3. Alpha stocks at 阿曬; beta (at the chest) sees it and packs.
	var first:=await succeed(alpha,SR.STOCK_ACTION,SR.WORKER,"","case 3 alpha stocks a lot",[beta])
	await wait_until(func():return beta.revisit() is Dictionary,3.0)
	for c:Client in [alpha,beta]:
		expect(public_row(c)==row(1,0,0,0,0,0,false,0),"case 3 %s sees one sunny lot (%s)"%[c.label,public_row(c)])
	expect(int(alpha.bag().get("sea_salt",0))==15,"case 3 three sea_salt left alpha's bag")
	await succeed(beta,SR.PACK_ACTION,SR.CHEST,"kitchen","case 3 beta packs a kitchen basket",[alpha])
	await wait_until(func():return SR.packed_total(alpha.session.snapshot)==1,3.0)
	for c:Client in [alpha,beta]:
		expect(public_row(c)==row(1,0,1,0,0,1,false,0),"case 3 %s sees one basket, day 1 (%s)"%[c.label,public_row(c)])
	expect(int(beta.bag().get("fiber",0))==10,"case 3 two fiber left beta's bag")
	await refuse(beta,SR.PACK_ACTION,SR.CHEST,"pickle",SR.NEED_STOCK%[1,1],"case 3 beta needs another lot",[alpha])

	# 4. Replay of a used sequence is dropped.
	await settle([alpha,beta])
	var counts:=[alpha.notices.size(),beta.notices.size()]
	var before4:=marks_of([alpha,beta])
	alpha.session.request_action.rpc_id(1,int(first.sequence),SR.STOCK_ACTION,SR.WORKER,"",region_of(alpha),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==counts[0] and beta.notices.size()==counts[1],"case 4 re-sent sequence %d gets no notice"%int(first.sequence))
	expect(marks_of([alpha,beta])==before4,"case 4 re-sent sequence changes nothing on either end")

	# 5. Split work: alpha stocks five more lots, beta packs the rest and sends.
	for i in 5:await succeed(alpha,SR.STOCK_ACTION,SR.WORKER,"","case 5 alpha stocks lot %d"%(i+2),[beta])
	expect(int(alpha.bag().get("sea_salt",0))==0,"case 5 alpha's eighteen sea_salt are all in the shed")
	await refuse(alpha,SR.STOCK_ACTION,SR.WORKER,"",SR.STOCK_FULL,"case 5 seventh lot",[beta])
	await wait_until(func():return SR.stocked_total(beta.session.snapshot)==6,3.0)
	expect(SR.stocked_total(beta.session.snapshot)==6,"case 5 beta (at the chest) sees six lots")
	for i in 2:await succeed(beta,SR.PACK_ACTION,SR.CHEST,"kitchen","case 5 beta packs kitchen %d"%(i+2),[alpha])
	await refuse(beta,SR.PACK_ACTION,SR.CHEST,"kitchen",SR.QUOTA_FULL%["料理用",3,3,"醃漬用"],"case 5 kitchen quota full",[alpha])
	for i in 3:await succeed(beta,SR.PACK_ACTION,SR.CHEST,"pickle","case 5 beta packs pickle %d"%(i+1),[alpha])
	expect(int(beta.bag().get("fiber",0))==0 and int(beta.bag().get("sea_salt",0))==3,"case 5 beta used her twelve fiber; her own earned salt is untouched")
	var done:=await succeed(beta,SR.SEND_ACTION,SR.STOP,"","case 5 beta sends the batch from the chest spot",[alpha])
	expect(str(done.message)==SR.COMPLETE_OK,"case 5 completion message")
	await wait_until(func():return SR.completed(alpha.session.snapshot) and SR.completed(beta.session.snapshot),3.0)
	for c:Client in [alpha,beta]:
		expect(public_row(c)==row(6,0,3,3,0,1,true,1),"case 5 %s sees the completed record (%s)"%[c.label,public_row(c)])
	await refuse(beta,SR.SEND_ACTION,SR.STOP,"",SR.ALREADY_DONE,"case 5 send after completion",[alpha])

	# 6. Claims once each; the claim set stays private.
	await refuse(beta,SR.CLAIM_ACTION,SR.WORKER,"",SR.TOO_FAR,"case 6 beta claims from the chest",[alpha])
	await succeed(alpha,SR.CLAIM_ACTION,SR.WORKER,"","case 6 alpha claims",[beta])
	expect(int(alpha.bag().get(KIT,0))==1 and alpha.revisit().get("claimed_own")==true,"case 6 alpha holds one kit and sees her own claim")
	expect(beta.revisit().get("claimed_own")==false and int(beta.bag().get(KIT,0))==0,"case 6 beta does not see alpha's claim as hers")
	for c:Client in [alpha,beta]:private_check(c,[beta if c==alpha else alpha],"case 6")
	await refuse(alpha,SR.CLAIM_ACTION,SR.WORKER,"",SR.CLAIMED,"case 6 alpha claims twice",[beta])
	# Beta walks east, north and west round the apprentice pans to 阿曬.
	expect(await walk(beta,Vector2.RIGHT,func(me):return float(me.get("x",0.0))>=50.3,10.0),"case 6 beta walks east (x=%s)"%str(beta.me().get("x")))
	expect(await walk(beta,Vector2.UP,func(me):return float(me.get("y",99.0))<=18.7,10.0),"case 6 beta walks north (y=%s)"%str(beta.me().get("y")))
	expect(await walk(beta,Vector2.LEFT,func(me):return float(me.get("x",99.0))<=45.6,10.0),"case 6 beta walks west to 阿曬 (x=%s)"%str(beta.me().get("x")))
	await succeed(beta,SR.CLAIM_ACTION,SR.WORKER,"","case 6 beta claims",[alpha])
	expect(int(beta.bag().get(KIT,0))==1 and beta.revisit().get("claimed_own")==true,"case 6 beta holds one kit")
	await refuse(beta,SR.CLAIM_ACTION,SR.WORKER,"",SR.CLAIMED,"case 6 beta claims twice",[alpha])
	for c:Client in [alpha,beta]:private_check(c,[beta if c==alpha else alpha],"case 6 after both claims")

	# 7. Reconnect cannot re-claim.
	await leave(beta)
	beta=null
	await pause(0.3)
	beta=await join("beta",BETA,port)
	if not expect(joined(beta),"case 7 beta reconnects"):return false
	await settle([alpha,beta])
	expect(beta.revisit().get("claimed_own")==true and int(beta.bag().get(KIT,0))==1,"case 7 reconnected beta sees her own claim and kit")
	await refuse(beta,SR.CLAIM_ACTION,SR.WORKER,"",SR.CLAIMED,"case 7 reconnected beta cannot re-claim",[alpha])

	# 8. Normal shutdown → exact save.
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 8 server shuts down with a final save")
	var disk=read_disk()
	if not expect(disk is Dictionary,"case 8 save parses"):return false
	expect(disk_valid(disk),"case 8 saved world passes SaveSchema")
	var rec=disk.get(SR.STATE_KEY,{})
	expect(rec is Dictionary and rec.size()==7,"case 8 save: record has exactly seven fields")
	expect(text(canon(rec.get("stocked")))==text({"sunny":6}) and text(canon(rec.get("packed")))==text({"kitchen":3,"pickle":3}) and int(rec.get("rain_packs",-1))==0 and int(rec.get("day",-1))==1 and rec.get("completed")==true and int(rec.get("done_day",-1))==1,"case 8 save: stocked/packed/rain_packs/day/completed/done_day")
	var claimers:Array=rec.get("claimed",{}).keys()
	claimers.sort()
	var want:=[ALPHA,BETA]
	want.sort()
	expect(claimers==want and rec.claimed.values().all(func(v):return v==true),"case 8 save: exactly alpha and beta claimed")
	var da:Dictionary=disk.players[ALPHA].inventory
	var db:Dictionary=disk.players[BETA].inventory
	expect(int(da.get(KIT,0))==1 and int(db.get(KIT,0))==1,"case 8 save: one kit each")
	expect(int(da.get("sea_salt",0))==0 and int(db.get("fiber",0))==0 and int(db.get("sea_salt",0))==3,"case 8 save: stocked salt and packing fiber are gone, beta's own salt untouched")

	# 9. Restart; late joiner sees completion.
	var port2:=start_server()
	if not expect(port2>0,"case 9 restarted server hosts the same save"):return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	if not expect(joined(alpha) and joined(beta),"case 9 both rejoin"):return false
	await settle([alpha,beta])
	for c:Client in [alpha,beta]:
		expect(public_row(c)==row(6,0,3,3,0,1,true,1) and c.revisit().get("claimed_own")==true,"case 9 %s: restart consistent"%c.label)
	gamma=await join("gamma",GAMMA,port2)
	if not expect(joined(gamma),"case 9 late joiner gamma joins"):return false
	await settle([alpha,beta,gamma])
	expect(SR.completed(gamma.session.snapshot) and gamma.revisit().get("claimed_own")==false,"case 9 gamma sees the completed revisit, own flag false")
	expect(SR.claim_block(gamma.session.snapshot,gamma.bag())==SR.NOT_READY,"case 9 gamma's client helper: rake by hand in 北門 first")
	private_check(gamma,[alpha,beta],"case 9")
	await refuse(gamma,SR.CLAIM_ACTION,SR.WORKER,"",SR.WRONG_REGION,"case 9 gamma (at home) cannot claim",[alpha,beta])
	await leave(gamma)
	gamma=null
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 9 restarted server shuts down cleanly")
	var after=read_disk()
	expect(disk_valid(after) and text(after.get(SR.STATE_KEY))==text(disk.get(SR.STATE_KEY)) and after.players.has(GAMMA),"case 9 final save valid, record unchanged, gamma recorded")
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
