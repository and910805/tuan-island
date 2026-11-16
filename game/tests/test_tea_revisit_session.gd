extends SceneTree
## 第 40 章貓空與鶯歌回訪「茶罐大單」two-client Session acceptance over a real dedicated
## server and real WebSocket clients (modelled on test_jinguashi_revisit_session.gd).
##
## LEVEL: one machine, ONE Godot process. A dedicated server Session listens on a free
## 127.0.0.1 port (websocket transport); two client Sessions (alpha in 鶯歌, beta in 貓空)
## and later a late joiner (gamma) join over loopback, each in its own branch with its own
## SceneMultiplayer. Clients only read their own received snapshots. The server World is
## never touched after seeding; the on-disk save is read (file only) after shutdowns.
##
## SEEDED FIXTURE (disclosed): built offline in a World before the server starts and
## validated with SaveSchema. EARNED there through World.act (timers via World.step):
## alpha's and beta's two-packaging comparisons (tea_intro → tea_potter → tea_fire /
## tea_fire_take → pick / roast / take → pack light:jar → ship → sell → return → reclaim →
## pick / roast / take → pack light:fiber → ship → sell → tea_discuss), which leaves each
## of them one recycled jar (tea_returned_jar) that came back from the delivery, plus one
## deep roast each (pick / roast deep / take). Written directly: chapter_one.shipped /
## watered, board, picnic, travel_book.visited, alpha's 5 extra tea_worn_jar, beta's 4
## tea_light + 1 extra tea_deep (2 with her earned one), the standing spots (alpha 20.5,21.5 at the 鶯歌 potter; beta
## 26.5,21.5 at the 貓空 packer), receipts cleared. No tea_revisit key is preset. World
## time starts where the offline tea timers left it (day 1, spring) and only advances by
## the server's real-time ticks.
## Everything after the seed goes through client Sessions over the network. Beta walks
## (input_direction) from the packer to the 貓空 transfer, rides `transit` to 鶯歌 and walks
## to the potter to claim.
## Replay: the raw request_action RPC re-sent with alpha's already-used jar sequence
## number; Session drops it.
## NOT covered: multiple processes, TLS, latency/loss, crash durability (normal shutdowns
## only), season changes (rule level, test_tea_revisit.gd).
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const TR=preload("res://scripts/tea_revisit.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const KEY:="tea-revisit-session"
const ALPHA:="tearevisit-session-alpha-token"
const BETA:="tearevisit-session-beta-token"
const GAMMA:="tearevisit-session-gamma-token"
const KIT:="tea_ware_kit"
const A_SPOT:=Vector2(20.5,21.5)
const B_SPOT:=Vector2(26.5,21.5)
const TRANSFER:=Vector2i(12,25)

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
		return session.snapshot.get("tea_revisit",null)

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
	create_timer(110.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("TEA_REVISIT_SESSION watchdog fired before completion")
	print("TEA_REVISIT_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("TEA_REVISIT_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("TEA_REVISIT_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("TEA_REVISIT_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

func seed_act(w:World,token:String,action:String,p:Vector2i,extra:String="")->bool:
	serial+=1
	return bool(w.act(token,"seed-%d"%serial,action,p,extra).ok)

func place(w:World,token:String,region:String,at:Vector2)->void:
	var p:Dictionary=w.state.players[token]
	p["region"]=region
	p["x"]=at.x
	p["y"]=at.y
	if region in World.TRANSIT.ROUTE:p.travel_book.visited[region]=true

func tea(w:World,token:String,action:String,region:String,cell:Vector2i,extra:String="")->bool:
	place(w,token,region,Vector2(cell)+Vector2(0.5,1.5))
	return seed_act(w,token,action,cell,extra)

func seed_comparison(w:World,token:String)->bool:
	if not tea(w,token,"tea_intro","home",Tea.RECEIVER) or not tea(w,token,"tea_potter",Tea.YINGGE,Tea.POTTER):return false
	if not tea(w,token,"tea_fire",Tea.YINGGE,Tea.KILN) or not w.step(Tea.KILN_SECONDS,true) or not tea(w,token,"tea_fire_take",Tea.YINGGE,Tea.KILN):return false
	if not tea(w,token,"tea_pick",Tea.MAOKONG,Tea.TEA_NODES[0]) or not tea(w,token,"tea_roast",Tea.MAOKONG,Tea.ROASTER,"light"):return false
	if not w.step(Tea.ROAST_SECONDS.light,true) or not tea(w,token,"tea_take",Tea.MAOKONG,Tea.ROASTER):return false
	if not tea(w,token,"tea_pack",Tea.MAOKONG,Tea.PACKER,"light:jar") or not tea(w,token,"tea_ship",Tea.MAOKONG,Tea.PACKER):return false
	if not w.step(Tea.SHIPPING_SECONDS,true) or not tea(w,token,"tea_sell","home",Tea.RECEIVER) or not tea(w,token,"tea_return","home",Tea.RECEIVER):return false
	if not w.step(Tea.RETURN_SECONDS,true) or not tea(w,token,"tea_reclaim",Tea.MAOKONG,Tea.PACKER):return false
	if not tea(w,token,"tea_pick",Tea.MAOKONG,Tea.TEA_NODES[1]) or not tea(w,token,"tea_roast",Tea.MAOKONG,Tea.ROASTER,"light"):return false
	if not w.step(Tea.ROAST_SECONDS.light,true) or not tea(w,token,"tea_take",Tea.MAOKONG,Tea.ROASTER):return false
	if not tea(w,token,"tea_pack",Tea.MAOKONG,Tea.PACKER,"light:fiber") or not tea(w,token,"tea_ship",Tea.MAOKONG,Tea.PACKER):return false
	if not w.step(Tea.SHIPPING_SECONDS,true) or not tea(w,token,"tea_sell","home",Tea.RECEIVER) or not tea(w,token,"tea_discuss",Tea.MAOKONG,Tea.TEA_NPC):return false
	if not tea(w,token,"tea_pick",Tea.MAOKONG,Tea.TEA_NODES[2]) or not tea(w,token,"tea_roast",Tea.MAOKONG,Tea.ROASTER,"deep"):return false
	if not w.step(Tea.ROAST_SECONDS.deep,true) or not tea(w,token,"tea_take",Tea.MAOKONG,Tea.ROASTER):return false
	return Tea.own_record(w.state,token).comparison_complete==true

func seed_world(path:String)->bool:
	var w:=World.new()
	w.add_player(ALPHA,"alpha")
	w.add_player(BETA,"beta")
	var a:Dictionary=w.state.players[ALPHA]
	var b:Dictionary=w.state.players[BETA]
	w.state.chapter_one.shipped=true
	w.state.chapter_one.watered=true
	w.state["board"]=true
	w.state["picnic"]=true
	if not seed_comparison(w,ALPHA) or not seed_comparison(w,BETA):return false
	if int(a.inventory.get("tea_returned_jar",0))!=1 or int(b.inventory.get("tea_returned_jar",0))!=1 or int(b.inventory.get("tea_deep",0))!=1:return false
	a.inventory["tea_worn_jar"]=5
	b.inventory["tea_light"]=4
	b.inventory["tea_deep"]=2 # earned 1 + written 1
	place(w,ALPHA,"yingge",A_SPOT)
	place(w,BETA,"maokong",B_SPOT)
	for p:Dictionary in [a,b]:p["receipts"]={}
	w.active_tokens.clear()
	w.save_path=path
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.has(TR.STATE_KEY) or float(parsed.time)>=1440.0:return false
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
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty() and c.session.snapshot.get("tea_ceramics") is Dictionary

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
	expect(marks_of(everyone)==marks,"%s: bags and tea_revisit unchanged in every watching snapshot"%label)

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
	return text({"jars":rec.get("jars"),"filled":rec.get("filled"),"day":rec.get("day"),"completed":rec.get("completed"),"done_day":rec.get("done_day")})

func row(returned:int,worn:int,light:int,deep:int,day:int,completed:bool,done_day:int)->String:
	return text({"jars":{"tea_returned_jar":returned,"tea_worn_jar":worn},"filled":{"light":light,"deep":deep},"day":day,"completed":completed,"done_day":done_day})

func read_disk()->Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(save_path))

func disk_valid(disk:Variant)->bool:
	return disk is Dictionary and Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func region_of(c:Client)->String:
	return str(c.session.snapshot.get("region_id",""))

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("tea-revisit-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"SEEDED FIXTURE (two comparisons + their recycled jars and deep roasts earned offline; extra jars/tea/spots written; no tea_revisit) accepted by SaveSchema"):return false
	var probe:=World.new()
	if not expect(probe.load_world(save_path),"probe: seeded save loads"):return false
	probe.switch_region("maokong")
	var maokong_path:=true
	for x in range(14,27):
		if not probe.can_stand(Vector2(float(x)+0.5,21.5)):maokong_path=false
	for y in range(21,25):
		if not probe.can_stand(Vector2(14.0,float(y)+0.5)):maokong_path=false
	expect(probe.can_stand(B_SPOT) and maokong_path,"probe: 貓空 walk from the packer to the transfer is standable")
	probe.switch_region("yingge")
	var yingge_path:=probe.can_stand(A_SPOT) and probe.can_stand(Vector2(13.5,25.5))
	for y in range(21,26):
		if not probe.can_stand(Vector2(13.5,float(y)+0.5)):yingge_path=false
	for x in range(13,21):
		if not probe.can_stand(Vector2(float(x)+0.5,21.5)):yingge_path=false
	expect(yingge_path,"probe: 鶯歌 walk from the transfer arrival to the potter is standable")
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
	expect(region_of(alpha)=="yingge" and region_of(beta)=="maokong","alpha is in 鶯歌, beta in 貓空")
	print("TEA_REVISIT_SESSION_LABEL machine=single process=single transport=websocket loopback=127.0.0.1:%d clients=2(+late joiner) fixture=SEEDED(tea comparisons earned offline; jars,tea,spots) shutdown=normal-only"%port)

	# 1. Fresh: both ready, no record, spring order.
	for c:Client in [alpha,beta]:
		var snap:Dictionary=c.session.snapshot
		expect(c.revisit()==null and TR.player_ready(snap) and not TR.completed(snap),"case 1 %s: ready, no record yet"%c.label)
		expect(TR.today(snap)==1 and TR.order_season(snap)=="spring" and TR.order(snap)=={"light":4,"deep":2},"case 1 %s: day 1 spring order 4/2"%c.label)
		private_check(c,[beta if c==alpha else alpha],"case 1")
	expect(TR.jar_block(alpha.session.snapshot,"tea_returned_jar",alpha.bag())=="" and TR.fill_block(beta.session.snapshot,"deep",beta.bag())==TR.NEED_JARS%[0,0],"case 1 client helpers: alpha can hand a jar, beta must wait for one")

	# 2. Refusals leave both ends unchanged.
	await refuse(beta,TR.FILL_ACTION,TR.PACKER,"deep",TR.NEED_JARS%[0,0],"case 2 fill before any jar",[alpha])
	await refuse(alpha,TR.FILL_ACTION,TR.PACKER,"light",TR.WRONG_REGION_MAOKONG,"case 2 alpha fills from 鶯歌",[beta])
	await refuse(alpha,TR.JAR_ACTION,TR.POTTER,"tea_jar",TR.NEW_JAR,"case 2 a new jar is not recycled",[beta])
	await refuse(beta,TR.JAR_ACTION,TR.POTTER,"tea_returned_jar",TR.WRONG_REGION_YINGGE,"case 2 beta hands a jar in 貓空",[alpha])
	await refuse(beta,TR.SEND_ACTION,TR.PACKER,"",TR.NOT_FILLED%0,"case 2 send an empty order",[alpha])
	await refuse(alpha,TR.CLAIM_ACTION,TR.POTTER,"",TR.NOT_DONE,"case 2 claim before completion",[beta])

	# 3. Alpha hands in her earned jar in 鶯歌; beta (in 貓空) sees it and fills.
	var first:=await succeed(alpha,TR.JAR_ACTION,TR.POTTER,"tea_returned_jar","case 3 alpha hands in her recycled jar",[beta])
	await wait_until(func():return beta.revisit() is Dictionary,3.0)
	for c:Client in [alpha,beta]:
		expect(public_row(c)==row(1,0,0,0,0,false,0),"case 3 %s sees one checked jar (%s)"%[c.label,public_row(c)])
	expect(int(alpha.bag().get("tea_returned_jar",0))==0,"case 3 alpha's recycled jar left her bag")
	await succeed(beta,TR.FILL_ACTION,TR.PACKER,"deep","case 3 beta fills a deep jar",[alpha])
	await wait_until(func():return TR.filled_total(alpha.session.snapshot)==1,3.0)
	for c:Client in [alpha,beta]:
		expect(public_row(c)==row(1,0,0,1,1,false,0),"case 3 %s sees one filled, day 1 (%s)"%[c.label,public_row(c)])
	await refuse(beta,TR.FILL_ACTION,TR.PACKER,"deep",TR.NEED_JARS%[1,1],"case 3 beta needs another checked jar",[alpha])

	# 4. Replay of a used sequence is dropped.
	await settle([alpha,beta])
	var counts:=[alpha.notices.size(),beta.notices.size()]
	var before4:=marks_of([alpha,beta])
	alpha.session.request_action.rpc_id(1,int(first.sequence),TR.JAR_ACTION,TR.POTTER,"tea_worn_jar",region_of(alpha),int(alpha.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==counts[0] and beta.notices.size()==counts[1],"case 4 re-sent sequence %d gets no notice"%int(first.sequence))
	expect(marks_of([alpha,beta])==before4,"case 4 re-sent sequence changes nothing on either end")

	# 5. Split work: alpha checks five worn jars, beta fills the rest and sends.
	for i in 5:await succeed(alpha,TR.JAR_ACTION,TR.POTTER,"tea_worn_jar","case 5 alpha hands in worn jar %d"%(i+1),[beta])
	expect(int(alpha.bag().get("tea_worn_jar",0))==0,"case 5 alpha's five worn jars left her bag")
	await refuse(alpha,TR.JAR_ACTION,TR.POTTER,"tea_worn_jar",TR.JARS_FULL,"case 5 seventh jar",[beta])
	await wait_until(func():return TR.jars_total(beta.session.snapshot)==6,3.0)
	expect(TR.jars_total(beta.session.snapshot)==6,"case 5 beta (in 貓空) sees six checked jars")
	await succeed(beta,TR.FILL_ACTION,TR.PACKER,"deep","case 5 beta fills the second deep",[alpha])
	await refuse(beta,TR.FILL_ACTION,TR.PACKER,"deep",TR.QUOTA_FULL%["深焙",2,2,"淺焙"],"case 5 deep quota full",[alpha])
	for i in 4:await succeed(beta,TR.FILL_ACTION,TR.PACKER,"light","case 5 beta fills light %d"%(i+1),[alpha])
	expect(int(beta.bag().get("tea_light",0))==0 and int(beta.bag().get("tea_deep",0))==0,"case 5 beta used 4 light + 2 deep (her earned deep and the written one)")
	var done:=await succeed(beta,TR.SEND_ACTION,TR.PACKER,"","case 5 beta sends the big order",[alpha])
	expect(str(done.message)==TR.COMPLETE_OK,"case 5 completion message")
	await wait_until(func():return TR.completed(alpha.session.snapshot) and TR.completed(beta.session.snapshot),3.0)
	for c:Client in [alpha,beta]:
		expect(public_row(c)==row(1,5,4,2,1,true,1),"case 5 %s sees the completed record (%s)"%[c.label,public_row(c)])
	await refuse(beta,TR.SEND_ACTION,TR.PACKER,"",TR.ALREADY_DONE,"case 5 send after completion",[alpha])

	# 6. Claims once each; the claim set stays private.
	await refuse(beta,TR.CLAIM_ACTION,TR.POTTER,"",TR.WRONG_REGION_YINGGE,"case 6 beta claims from 貓空",[alpha])
	await succeed(alpha,TR.CLAIM_ACTION,TR.POTTER,"","case 6 alpha claims",[beta])
	expect(int(alpha.bag().get(KIT,0))==1 and alpha.revisit().get("claimed_own")==true,"case 6 alpha holds one kit and sees her own claim")
	expect(beta.revisit().get("claimed_own")==false and int(beta.bag().get(KIT,0))==0,"case 6 beta does not see alpha's claim as hers")
	for c:Client in [alpha,beta]:private_check(c,[beta if c==alpha else alpha],"case 6")
	await refuse(alpha,TR.CLAIM_ACTION,TR.POTTER,"",TR.CLAIMED,"case 6 alpha claims twice",[beta])
	# Beta walks to the 貓空 transfer, rides to 鶯歌 and walks to the potter.
	expect(await walk(beta,Vector2.LEFT,func(me):return float(me.get("x",99.0))<=14.2,12.0),"case 6 beta walks west (x=%s)"%str(beta.me().get("x")))
	expect(await walk(beta,Vector2.DOWN,func(me):return float(me.get("y",0.0))>=24.0,8.0),"case 6 beta walks south to the transfer (y=%s)"%str(beta.me().get("y")))
	var ride:=await act(beta,"transit",TRANSFER,"yingge")
	expect(ride.ok,"case 6 beta rides the transfer to 鶯歌 (%s)"%str(ride.message))
	await wait_until(func():return region_of(beta)=="yingge",4.0)
	await settle([beta])
	expect(region_of(beta)=="yingge","case 6 beta arrived in 鶯歌")
	expect(await walk(beta,Vector2.UP,func(me):return float(me.get("y",99.0))<=21.8,10.0),"case 6 beta walks north (y=%s)"%str(beta.me().get("y")))
	expect(await walk(beta,Vector2.RIGHT,func(me):return float(me.get("x",0.0))>=18.2,10.0),"case 6 beta walks to the potter (x=%s)"%str(beta.me().get("x")))
	await succeed(beta,TR.CLAIM_ACTION,TR.POTTER,"","case 6 beta claims",[alpha])
	expect(int(beta.bag().get(KIT,0))==1 and beta.revisit().get("claimed_own")==true,"case 6 beta holds one kit")
	await refuse(beta,TR.CLAIM_ACTION,TR.POTTER,"",TR.CLAIMED,"case 6 beta claims twice",[alpha])
	for c:Client in [alpha,beta]:private_check(c,[beta if c==alpha else alpha],"case 6 after both claims")

	# 7. Reconnect cannot re-claim.
	await leave(beta)
	beta=null
	await pause(0.3)
	beta=await join("beta",BETA,port)
	if not expect(joined(beta),"case 7 beta reconnects"):return false
	await settle([alpha,beta])
	expect(beta.revisit().get("claimed_own")==true and int(beta.bag().get(KIT,0))==1,"case 7 reconnected beta sees her own claim and kit")
	await refuse(beta,TR.CLAIM_ACTION,TR.POTTER,"",TR.CLAIMED,"case 7 reconnected beta cannot re-claim",[alpha])

	# 8. Normal shutdown → exact save.
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 8 server shuts down with a final save")
	var disk=read_disk()
	if not expect(disk is Dictionary,"case 8 save parses"):return false
	expect(disk_valid(disk),"case 8 saved world passes SaveSchema")
	var rec=disk.get(TR.STATE_KEY,{})
	expect(rec is Dictionary and rec.size()==6,"case 8 save: record has exactly six fields")
	expect(text(canon(rec.get("jars")))==text({"tea_returned_jar":1,"tea_worn_jar":5}) and text(canon(rec.get("filled")))==text({"deep":2,"light":4}) and int(rec.get("day",-1))==1 and rec.get("completed")==true and int(rec.get("done_day",-1))==1,"case 8 save: jars/filled/day/completed/done_day")
	var claimers:Array=rec.get("claimed",{}).keys()
	claimers.sort()
	var want:=[ALPHA,BETA]
	want.sort()
	expect(claimers==want and rec.claimed.values().all(func(v):return v==true),"case 8 save: exactly alpha and beta claimed")
	var da:Dictionary=disk.players[ALPHA].inventory
	var db:Dictionary=disk.players[BETA].inventory
	expect(int(da.get(KIT,0))==1 and int(db.get(KIT,0))==1,"case 8 save: one kit each")
	expect(int(da.get("tea_returned_jar",0))==0 and int(da.get("tea_worn_jar",0))==0 and int(db.get("tea_light",0))==0 and int(db.get("tea_deep",0))==0 and int(db.get("tea_returned_jar",0))==1,"case 8 save: handed jars and filled tea are gone, beta's own jar untouched")

	# 9. Restart; late joiner sees completion.
	var port2:=start_server()
	if not expect(port2>0,"case 9 restarted server hosts the same save"):return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	if not expect(joined(alpha) and joined(beta),"case 9 both rejoin"):return false
	await settle([alpha,beta])
	for c:Client in [alpha,beta]:
		expect(public_row(c)==row(1,5,4,2,1,true,1) and c.revisit().get("claimed_own")==true,"case 9 %s: restart consistent"%c.label)
	gamma=await join("gamma",GAMMA,port2)
	if not expect(joined(gamma),"case 9 late joiner gamma joins"):return false
	await settle([alpha,beta,gamma])
	expect(TR.completed(gamma.session.snapshot) and gamma.revisit().get("claimed_own")==false,"case 9 gamma sees the completed revisit, own flag false")
	expect(TR.claim_block(gamma.session.snapshot,gamma.bag())==TR.NOT_READY,"case 9 gamma's client helper: finish the tea comparison first")
	private_check(gamma,[alpha,beta],"case 9")
	await refuse(gamma,TR.CLAIM_ACTION,TR.POTTER,"",TR.WRONG_REGION_YINGGE,"case 9 gamma (at home) cannot claim",[alpha,beta])
	await leave(gamma)
	gamma=null
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 9 restarted server shuts down cleanly")
	var after=read_disk()
	expect(disk_valid(after) and text(after.get(TR.STATE_KEY))==text(disk.get(TR.STATE_KEY)) and after.players.has(GAMMA),"case 9 final save valid, record unchanged, gamma recorded")
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
