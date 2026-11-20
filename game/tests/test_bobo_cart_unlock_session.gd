extends SceneTree
## Bobo N03-2「動不了的礦車」→ world-wide 礦車搬運坑道 unlock, independent two-client Session
## acceptance over a real dedicated server and real WebSocket clients.
## (Standalone: setup pattern copied from test_gold_panning_session.gd; nothing inherited, nothing edited.)
##
## LEVEL: one machine, ONE Godot process. A server Session listens on a free 127.0.0.1 port
## (websocket transport); two client Sessions (repairer, guest) join over loopback, each in its own
## branch with its own SceneMultiplayer. LOCAL SAME-PROCESS FIXTURE ONLY: no public service,
## no production code or save is touched, the save lives in a fresh TEMP folder.
##
## SEEDED FIXTURE (disclosed, written offline before the server starts, validated by SaveSchema):
## repairer: region jinguashi, standing on a standable cell next to Bobo (World.bond_place), Bobo bond
## 6 points (stage 2), bag copper_ingot 5 / woodwork_parts 3 (one spare of each), NO bond_goals.
## guest: region jinguashi on the gallery entrance (PARTY_CART.SURFACE_PORTAL), no bond, no bond_goals.
## PLAYED over the network: stage-2 completion (session.perform resident_goal "bobo:2:siding:"),
## enter / exit of the gallery, the raw request_action portal attempt, disconnect + server restart.
## ONE disclosed fixture teleport (server world write) only if the arrival cell is out of reach of the exit.
## NOT covered: multiple processes, TLS, latency/loss, crash durability (normal shutdowns only).
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const PC=preload("res://scripts/party_cart.gd")
const KEY:="bobo-cart-unlock-session"
const REPAIRER:="bobo-unlock-repairer-token"
const GUEST:="bobo-unlock-guest-token"
const UNLOCK_KEY:="party_cart_unlocked"
const CHOICE:="siding"
const COPPER:="copper_ingot"
const PARTS:="woodwork_parts"
const HALF:=Vector2(0.5,0.5)

class Client:
	var label:=""
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
	func region()->String:
		return str(session.snapshot.get("region_id",""))
	func unlocked()->Variant:
		return session.snapshot.get("party_cart_unlocked",null)
	func bobo_row()->Dictionary:
		var goals=session.snapshot.get("resident_goals",{})
		if not goals is Dictionary:return {}
		var bobo=goals.get("bobo",{})
		if not bobo is Dictionary:return {}
		var row=bobo.get("2",{})
		return row if row is Dictionary else {}

var checks:=0
var failures:=0
var serial:=0
var folder:=""
var save_path:=""
var server
var server_branch:Node
var finished:=false
var bobo_cell:=Vector2i.ZERO
var repair_spot:=Vector2.ZERO
var repairer:Client
var guest:Client

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)
	return ok

func _initialize()->void:
	create_timer(100.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("BOBO_CART_UNLOCK_SESSION watchdog fired before completion")
	print("BOBO_CART_UNLOCK_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var completed:=await scenario()
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("BOBO_CART_UNLOCK_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("BOBO_CART_UNLOCK_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

func seed_world(path:String)->bool:
	var w:=World.new()
	w.add_player(REPAIRER,"repairer")
	w.add_player(GUEST,"guest")
	var bobo:Array=World.bond_place(w.state,"bobo")
	if str(bobo[0])!="jinguashi":return false
	bobo_cell=bobo[1]
	w.switch_region("jinguashi")
	var best:=Vector2.ZERO
	var best_d:=99.0
	for dy in range(-2,3):
		for dx in range(-2,3):
			var pos:=Vector2(bobo_cell.x+dx,bobo_cell.y+dy)+HALF
			var d:=pos.distance_to(Vector2(bobo_cell)+HALF)
			if d<0.9 or d>2.2 or not w.can_stand(pos):continue
			if d<best_d:
				best_d=d
				best=pos
	w.switch_region("home")
	if best==Vector2.ZERO:return false
	repair_spot=best
	var rp:Dictionary=w.state.players[REPAIRER]
	rp.region="jinguashi"
	rp.x=repair_spot.x
	rp.y=repair_spot.y
	rp.bonds={"bobo":{"points":6,"talk_day":-1,"gift_day":-1}}
	rp.inventory[COPPER]=5
	rp.inventory[PARTS]=3
	rp.erase("bond_goals")
	var gp:Dictionary=w.state.players[GUEST]
	gp.region="jinguashi"
	gp.x=float(PC.SURFACE_PORTAL.x)+0.5
	gp.y=float(PC.SURFACE_PORTAL.y)+0.5
	gp.erase("bond_goals")
	w.active_tokens.clear()
	w.save_path=path
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:return false
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
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty() and c.session.snapshot.has("region_id")

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

func act(c:Client,action:String,p:Vector2i,extra:String="")->Dictionary:
	await pause(0.15) # session rate limit
	var before:=c.notices.size()
	c.session.perform(action,p,extra)
	var replied:=await wait_until(func():return c.notices.size()>before,4.0)
	if not replied:return {"replied":false,"ok":false,"message":""}
	var reply:Array=c.notices[before]
	return {"replied":true,"ok":bool(reply[1]),"message":str(reply[0])}

## Raw request_action RPC with a fresh sequence number (bypasses Session.perform's local helpers).
func raw(c:Client,action:String,p:Vector2i,extra:String)->Dictionary:
	await pause(0.15)
	var before:=c.notices.size()
	c.session.counter+=1
	c.session.request_action.rpc_id(1,c.session.counter,action,p,extra,c.region(),int(c.me().get("travel_epoch",0)))
	var replied:=await wait_until(func():return c.notices.size()>before,4.0)
	if not replied:return {"replied":false,"ok":false,"message":""}
	var reply:Array=c.notices[before]
	return {"replied":true,"ok":bool(reply[1]),"message":str(reply[0])}

# ---------------------------------------------------------------- helpers --

static func canon(d:Variant)->Dictionary:
	var out:={}
	if not d is Dictionary:return {"<invalid>":-1}
	for item in d:
		if int(d[item])!=0:out[str(item)]=int(d[item])
	return out

static func text(d:Variant)->String:
	return JSON.stringify(d,"",true)

## Private-state check: no raw token, and (for a client that does not own the goal) no bond_goals
## and no chosen option anywhere in its snapshot.
func private_check(c:Client,owns_goal:bool,label:String)->void:
	var dump:=JSON.stringify(c.session.snapshot)
	expect(not dump.contains(REPAIRER) and not dump.contains(GUEST),"%s: %s's snapshot contains no raw token"%[label,c.label])
	var people=c.session.snapshot.get("players",{})
	var leaked:=false
	if people is Dictionary:
		for id in people:
			if str(id)!=c.session.own_id and people[id] is Dictionary and (people[id].has("bond_goals") or people[id].has("bonds")):leaked=true
	expect(not leaked,"%s: %s sees no other player's bond_goals/bonds"%[label,c.label])
	if not owns_goal:
		expect(not dump.contains("bond_goals") and not dump.contains("\"%s\""%CHOICE),"%s: %s's snapshot has no bond_goals and no '%s' choice"%[label,c.label,CHOICE])
		var row:=c.bobo_row()
		expect(str(row.get("state",""))!="done" and str(row.get("choice",""))=="","%s: %s's own Bobo stage-2 view is not done and has no choice (%s)"%[label,c.label,text(row)])

func disk_players()->Dictionary:
	var disk=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not disk is Dictionary or not disk.get("players") is Dictionary:return {}
	return disk.players

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("bobo-cart-unlock-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"SEEDED FIXTURE (repairer beside Bobo with bond 6 + 5 copper_ingot/3 woodwork_parts, guest at gallery entrance, no bond_goals) accepted by SaveSchema"):return false
	var port:=start_server()
	if not expect(port>0,"server Session hosts on 127.0.0.1 (websocket)"):return false
	repairer=await join("repairer",REPAIRER,port)
	guest=await join("guest",GUEST,port)
	if not expect(joined(repairer) and joined(guest),"repairer and guest joined over loopback"):return false
	expect(server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and repairer.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer,"server and clients use WebSocketMultiplayerPeer")
	expect(repairer.session.world==null and guest.session.world==null,"client Sessions hold no World")
	print("BOBO_CART_UNLOCK_SESSION_LABEL fixture=SEEDED-LOCAL machine=same process=single transport=websocket loopback=127.0.0.1:%d public-service=none production=untouched shutdown=normal-only"%port)
	await wait_until(func():return repairer.unlocked()!=null and guest.unlocked()!=null,4.0)

	# 1. Before: both clients receive an explicit false over the wire.
	expect(repairer.region()=="jinguashi" and guest.region()=="jinguashi","both are in Jinguashi (%s / %s)"%[repairer.region(),guest.region()])
	expect(repairer.unlocked() is bool and repairer.unlocked()==false,"1 repairer receives explicit party_cart_unlocked=false (%s)"%str(repairer.unlocked()))
	expect(guest.unlocked() is bool and guest.unlocked()==false,"1 guest receives explicit party_cart_unlocked=false (%s)"%str(guest.unlocked()))
	expect(repairer.bag().get(COPPER,0)==5 and repairer.bag().get(PARTS,0)==3,"1 repairer holds 5 copper_ingot / 3 woodwork_parts")
	private_check(guest,false,"1")
	private_check(repairer,false,"1")

	# 2. Guest raw portal action is rejected; nothing moves.
	var denied:=await raw(guest,PC.ACTION,PC.SURFACE_PORTAL,"enter")
	expect(denied.replied and not denied.ok,"2 guest's raw portal 'enter' is rejected (replied=%s ok=%s '%s')"%[str(denied.replied),str(denied.ok),str(denied.message)])
	await pause(0.3)
	expect(guest.region()=="jinguashi" and guest.unlocked()==false,"2 guest stays in Jinguashi, still locked (%s)"%guest.region())

	# 3. Repairer submits stage 2 through the ordinary Session.perform from their own client.
	var before_bag:=canon(repairer.bag())
	var guest_bag:=canon(guest.bag())
	var extra:="bobo:2:%s:"%CHOICE
	var fix:=await act(repairer,Goals.ACTION,bobo_cell,extra)
	expect(fix.replied and fix.ok,"3 repairer's stage-2 submit succeeds ('%s')"%str(fix.message))
	await wait_until(func():return int(repairer.bag().get(COPPER,0))==1 and guest.unlocked()==true,4.0)
	var after_bag:=canon(repairer.bag())
	var want:=before_bag.duplicate()
	want[COPPER]=int(want[COPPER])-4
	want[PARTS]=int(want[PARTS])-2
	expect(after_bag==canon(want),"3 host debited exactly 4 copper_ingot and 2 woodwork_parts (%s -> %s)"%[text(before_bag),text(after_bag)])
	expect(str(repairer.bobo_row().get("state",""))=="done" and str(repairer.bobo_row().get("choice",""))==CHOICE,"3 repairer's own view shows stage 2 done with '%s' (%s)"%[CHOICE,text(repairer.bobo_row())])
	expect(guest.unlocked() is bool and guest.unlocked()==true,"3 guest now receives party_cart_unlocked=true (%s)"%str(guest.unlocked()))
	expect(canon(guest.bag())==guest_bag,"3 guest's bag unchanged")
	private_check(guest,false,"3")
	var again:=await act(repairer,Goals.ACTION,bobo_cell,extra)
	expect(again.replied and not again.ok and canon(repairer.bag())==after_bag,"3 repeating stage 2 is refused and debits nothing ('%s')"%str(again.message))

	# 4. Guest enters then exits correctly.
	var entered:=await act(guest,PC.ACTION,PC.SURFACE_PORTAL,"enter")
	expect(entered.replied and entered.ok,"4 guest enters the gallery ('%s')"%str(entered.message))
	await wait_until(func():return guest.region()==PC.REGION,4.0)
	expect(guest.region()==PC.REGION,"4 guest's snapshot region is %s (%s)"%[PC.REGION,guest.region()])
	var exit_at:=Vector2(PC.EXIT)+HALF
	var spot:=Vector2(float(guest.me().get("x",-99.0)),float(guest.me().get("y",-99.0)))
	if spot.distance_to(exit_at)>3.0:
		server.world.state.players[GUEST].x=exit_at.x # FIXTURE TELEPORT (disclosed): arrival is out of reach of the exit
		server.world.state.players[GUEST].y=exit_at.y
		await wait_until(func():return Vector2(float(guest.me().get("x",-99.0)),float(guest.me().get("y",-99.0))).distance_to(exit_at)<0.1,3.0)
		print("BOBO_CART_UNLOCK_SESSION fixture teleport used for guest before exit")
	var left:=await act(guest,PC.ACTION,PC.EXIT,"exit")
	expect(left.replied and left.ok,"4 guest exits the gallery ('%s')"%str(left.message))
	await wait_until(func():return guest.region()=="jinguashi",4.0)
	expect(guest.region()=="jinguashi","4 guest is back in Jinguashi (%s)"%guest.region())
	await wait_until(func():return guest.unlocked()==true,3.0)
	private_check(guest,false,"4")

	# 5. Stop, restart on the same save, rejoin: still true; the debit and choice are on disk.
	await leave(repairer)
	await leave(guest)
	repairer=null
	guest=null
	expect(await stop_server(),"5 server shuts down with a final save")
	var players:=disk_players()
	var saved:Dictionary=players.get(REPAIRER,{})
	expect(str(saved.get("bond_goals",{}).get("bobo",{}).get("2",""))==CHOICE,"5 save: repairer's bond_goals.bobo.2 is '%s'"%CHOICE)
	expect(int(saved.get("inventory",{}).get(COPPER,0))==1 and int(saved.get("inventory",{}).get(PARTS,0))==1,"5 save: repairer bag copper_ingot 1 / woodwork_parts 1")
	expect(not players.get(GUEST,{}).has("bond_goals"),"5 save: guest has no bond_goals")
	var port2:=start_server()
	if not expect(port2>0,"5 restarted server hosts the same save file"):return false
	repairer=await join("repairer",REPAIRER,port2)
	guest=await join("guest",GUEST,port2)
	if not expect(joined(repairer) and joined(guest),"5 both rejoin after the restart"):return false
	await wait_until(func():return guest.unlocked()!=null and repairer.unlocked()!=null,4.0)
	expect(guest.unlocked() is bool and guest.unlocked()==true,"5 guest confirms party_cart_unlocked=true after restart (%s)"%str(guest.unlocked()))
	expect(repairer.unlocked() is bool and repairer.unlocked()==true,"5 repairer confirms true after restart (%s)"%str(repairer.unlocked()))
	private_check(guest,false,"5")
	return true

func teardown()->void:
	for c in [repairer,guest]:
		if c!=null and is_instance_valid(c.session) and not c.session.shutting_down:
			c.session.shutdown()
	await pause(0.2)
	if server!=null and is_instance_valid(server) and server.world!=null:
		expect(server.shutdown(),"final server shutdown saves cleanly")
	await pause(0.2)
	for c in [repairer,guest]:
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
