extends SceneTree
## T018 manual harvest per-item capacity: two-client Session acceptance over a real dedicated
## server and real WebSocket clients. Harness copied from test_season_dormancy_session.gd.
##
## LEVEL: one machine, ONE Godot process. A dedicated server Session listens on a free
## 127.0.0.1 port (websocket transport); two client Sessions (alpha = plot owner, beta =
## observer) join over loopback, each in its own branch with its own SceneMultiplayer.
## Clients only read their own received snapshots and their own notices (Session.notice,
## delivered by the server's receive_notice RPC to the requesting peer only). The on-disk
## save is read (file only) after the normal shutdown.
##
## SEEDED FIXTURE (disclosed): built offline in a World before the server starts and validated
## with SaveSchema. The plot cell is found by a throwaway probe World (first tillable home
## cell near World.SPAWN with a standable alpha spot within reach, plus a distinct beta spot).
## EARNED there through World.act: alpha tills the plot and sows wheat from the starter bag.
## PRESET list (every direct write is marked # PRESET and counted; the count is printed):
##   seed : (1) world time = summer day 15 (sunny, wheat in season); (2,3) alpha x,y;
##          (4,5) beta x,y; (6) wheat growth = ripe (World.CROPS.wheat.time);
##          (7) alpha inventory.wheat = 999999999.                              -> 7 seed presets
##   live : (8) server alpha inventory.wheat = 999999998 (makes room for exactly one yield-2
##          harvest; stands in for selling/using wheat).                         -> 1 live preset
##   total: 8 presets.
## A separate contention phase resets alpha's stack and restores one ripe
## shared crop per round. Both clients race and replay their sequences.
## NOT covered: multiple processes, TLS, latency/loss, crash durability (normal shutdown only),
## the player.harvests >= 1e9 refusal branch (would need a 9th preset; rule-level test only),
## friend harvest_access, greenhouse plots.
## API notes: refusals ARE delivered to the requester (Session._action -> _send_notice ->
## receive_notice RPC -> Session.notice(message, false)); foreign players' inventories are
## erased from each recipient's snapshot in Session._send_snapshot. No harness gap found.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Weather=preload("res://scripts/weather.gd")
const TAG:="MANUAL_HARVEST_CAPACITY_SESSION"
const KEY:="manual-harvest-capacity-session"
const ALPHA:="harvest-capacity-session-alpha-token"
const BETA:="harvest-capacity-session-beta-token"
const DAY:=1440.0
const T_SUMMER1:=14.0*DAY+200.0
const FULL:=999999999
const ROOM:=999999998
const CAP:=1000000000
const CAP_MARK:="已達上限"

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
		var mine=people.get(session.own_id,{})
		return mine if mine is Dictionary else {}
	func other(public_id:String)->Dictionary:
		var people=session.snapshot.get("players",{})
		if not people is Dictionary:return {}
		var p=people.get(public_id,{})
		return p if p is Dictionary else {}
	func bag()->Dictionary:
		var inv=me().get("inventory",{})
		return inv if inv is Dictionary else {}
	func crop(k:String)->Dictionary:
		var crops=session.snapshot.get("crops",{})
		if not crops is Dictionary:return {}
		var c=crops.get(k,{})
		return c if c is Dictionary else {}

var checks:=0
var failures:=0
var serial:=0
var presets:=0
var folder:=""
var save_path:=""
var server
var server_branch:Node
var finished:=false
var alpha:Client
var beta:Client
var plot:=Vector2i(-1,-1)
var k1:=""
var a_spot:=Vector2(-1,-1)
var b_spot:=Vector2(-1,-1)

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)
	return ok

func _initialize()->void:
	create_timer(55.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("%s watchdog fired before completion"%TAG)
	print("%s presets=%d"%[TAG,presets])
	failures+=1
	print("MANUAL_HARVEST_CAPACITY_SESSION checks=%d failures=%d"%[checks,failures])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("%s kept temp folder for inspection: %s"%[TAG,folder])
	if finished:return
	finished=true
	print("%s duration_ms=%d"%[TAG,Time.get_ticks_msec()-started])
	print("%s presets=%d"%[TAG,presets])
	print("MANUAL_HARVEST_CAPACITY_SESSION checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

# ---------------------------------------------------------------- fixture --

## Every direct state write goes through here (counted, marked # PRESET at the call site).
func preset(d:Dictionary,field:String,value:Variant)->void:
	d[field]=value
	presets+=1

func seed_act(w:World,token:String,action:String,p:Vector2i,extra:String="")->bool:
	serial+=1
	var r:Dictionary=w.act(token,"seed-%d"%serial,action,p,extra)
	if not bool(r.get("ok",false)):print("%s seed action %s %s %s refused: %s"%[TAG,action,str(p),extra,str(r.get("message",""))])
	return bool(r.get("ok",false))

static func centre(t:Vector2i)->Vector2:
	return Vector2(t)+Vector2(0.5,0.5)

## Standable tile centre within 3.0 of the target (`taken` tiles excluded).
static func stand_spot(w:World,target:Vector2i,taken:Array)->Vector2:
	for dy in range(-3,4):
		for dx in range(-3,4):
			var tile:=target+Vector2i(dx,dy)
			if tile in taken:continue
			var at:=centre(tile)
			if not w.can_stand(at):continue
			if at.distance_to(centre(target))<=3.0:return at
	return Vector2(-1,-1)

static func fresh_probe()->World:
	var w:=World.new()
	w.add_player(ALPHA,"alpha")
	w.add_player(BETA,"beta")
	return w

## Throwaway probe World: the first tillable home cell near the spawn.
func find_layout()->bool:
	var cands:Array=[]
	for y in range(26,42):
		for x in range(30,50):cands.append(Vector2i(x,y))
	cands.sort_custom(func(a:Vector2i,b:Vector2i)->bool:return centre(a).distance_squared_to(World.SPAWN)<centre(b).distance_squared_to(World.SPAWN))
	var probe:=fresh_probe()
	for cand:Vector2i in cands:
		var spot:=stand_spot(probe,cand,[cand])
		if spot.x<0:continue
		var who:Dictionary=probe.state.players[ALPHA]
		who["x"]=spot.x
		who["y"]=spot.y
		serial+=1
		if not bool(probe.act(ALPHA,"probe-%d"%serial,"hoe",cand).get("ok",false)):continue
		var bspot:=stand_spot(probe,cand,[cand,Vector2i(floori(spot.x),floori(spot.y))])
		if bspot.x<0:
			probe=fresh_probe()
			continue
		plot=cand
		k1=World.key(cand)
		a_spot=spot
		b_spot=bspot
		return true
	return false

func seed_world(path:String)->bool:
	if not find_layout():
		print("%s no tillable plot found near the spawn"%TAG)
		return false
	var w:=World.new()
	w.add_player(ALPHA,"alpha")
	w.add_player(BETA,"beta")
	preset(w.state,"time",T_SUMMER1) # PRESET 1 summer day 15
	var a:Dictionary=w.state.players[ALPHA]
	preset(a,"x",a_spot.x) # PRESET 2
	preset(a,"y",a_spot.y) # PRESET 3
	var b:Dictionary=w.state.players[BETA]
	preset(b,"x",b_spot.x) # PRESET 4
	preset(b,"y",b_spot.y) # PRESET 5
	if not seed_act(w,ALPHA,"hoe",plot):return false
	if not seed_act(w,ALPHA,"seed",plot,"wheat"):return false
	if not w.state.crops.has(k1):return false
	preset(w.state.crops[k1],"growth",float(World.CROPS.wheat.time)) # PRESET 6 ripe wheat
	a=w.state.players[ALPHA]
	var inv:Dictionary=a.inventory
	preset(inv,"wheat",FULL) # PRESET 7 alpha holds 999999999 wheat
	w.active_tokens.clear()
	w.save_path=path
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:return false
	var crops=parsed.get("crops",{})
	if not crops is Dictionary:return false
	if disk_row(crops.get(k1))!=want("wheat",float(World.CROPS.wheat.time),1,false):return false
	if disk_wheat(parsed,ALPHA)!=FULL:return false
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
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty() and c.session.snapshot.get("crops") is Dictionary

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

static func text(d:Variant)->String:
	return JSON.stringify(d,"",true)

static func row_of(c:Dictionary)->String:
	if c.is_empty():return "none"
	return text({"kind":str(c.get("kind","<missing>")),"growth":float(c.get("growth",-1.0)),"remaining":int(c.get("remaining",-1)),"wet":c.get("wet")==true})

static func disk_row(c:Variant)->String:
	if not c is Dictionary:return "none"
	return row_of(c)

static func want(kind:String,growth:float,remaining:int,wet:bool)->String:
	return text({"kind":kind,"growth":growth,"remaining":remaining,"wet":wet})

func server_ok()->bool:
	return server!=null and is_instance_valid(server) and server.world!=null

func srv_player(token:String)->Dictionary:
	if not server_ok():return {}
	var people=server.world.state.get("players",{})
	var p=people.get(token,{}) if people is Dictionary else {}
	return p if p is Dictionary else {}

func srv_crop(k:String)->Dictionary:
	if not server_ok():return {"<no server>":true}
	var crops=server.world.state.get("crops",{})
	var c=crops.get(k,{}) if crops is Dictionary else {}
	return c.duplicate(true) if c is Dictionary else {}

func srv_wheat(token:String)->int:
	var inv=srv_player(token).get("inventory",{})
	return int(inv.get("wheat",-1)) if inv is Dictionary else -1

func srv_harvests(token:String)->int:
	return int(srv_player(token).get("harvests",-1))

func wheat(c:Client)->int:
	return int(c.bag().get("wheat",-1))

## Every listed client and the server hold `row` for the plot key.
func all_see(clients:Array,k:String,row:String,seconds:float)->bool:
	return await wait_until(func():
		if row_of(srv_crop(k))!=row:return false
		for c in clients:
			if c==null or row_of(c.crop(k))!=row:return false
		return true,seconds)

func seen_text(clients:Array,k:String)->String:
	var parts:Array=clients.map(func(c):return "%s %s"%[c.label,row_of(c.crop(k))])
	parts.append("server %s"%row_of(srv_crop(k)))
	return str(parts)

func read_disk()->Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(save_path))

func disk_valid(disk:Variant)->bool:
	return disk is Dictionary and Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

static func disk_wheat(disk:Variant,token:String)->int:
	if not disk is Dictionary:return -1
	var people=disk.get("players",{})
	var p=people.get(token,{}) if people is Dictionary else {}
	var inv=p.get("inventory",{}) if p is Dictionary else {}
	return int(inv.get("wheat",-1)) if inv is Dictionary else -1

static func disk_crop(disk:Variant,k:String)->Variant:
	if not disk is Dictionary:return null
	var crops=disk.get("crops",{})
	return crops.get(k) if crops is Dictionary else null

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	expect(int(World.CROPS.wheat.get("yield",0))==2 and not World.CROPS.wheat.has("cycles"),"static: wheat yield 2, single harvest")
	expect(World.CROP_SEASONS.get("wheat",[]).has("summer"),"static: wheat grows in summer")
	expect(Weather.season_on_day(Weather.day_index(T_SUMMER1))=="summer" and not Weather.rains(Weather.day_index(T_SUMMER1)),"static: preset day is summer and not rainy")
	expect(FULL>CAP-2 and ROOM<=CAP-2,"static: 999999999 has no room for 2 wheat, 999999998 has exactly room")
	folder=OS.get_environment("TEMP").path_join("manual-harvest-capacity-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"SEEDED FIXTURE (plot tilled + wheat sown offline; time, spots, ripe growth, wheat 999999999 written) accepted by SaveSchema"):return false
	print("%s layout plot=%s alpha=%s beta=%s"%[TAG,k1,str(a_spot),str(b_spot)])
	var port:=start_server()
	if not expect(port>0,"server Session hosts on 127.0.0.1 (websocket)"):return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	if not expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback"):return false
	expect(server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer,"server and clients use WebSocketMultiplayerPeer")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World")
	await settle([alpha,beta])
	print("%s_LABEL machine=single process=single transport=websocket loopback=127.0.0.1:%d clients=2 fixture=SEEDED capacity_presets=8 contention_presets=101 shutdown=normal-only"%[TAG,port])

	var ab:Array=[alpha,beta]
	var alpha_public:=ALPHA.sha256_text().left(16)
	var ripe_row:=want("wheat",float(World.CROPS.wheat.time),1,false)
	var empty_row:=want("",0.0,0,false)

	# 1. Baseline: both see the ripe wheat; alpha sees 999999999 wheat; beta does not see it.
	expect(await all_see(ab,k1,ripe_row,3.0),"case 1 both see the ripe wheat %s"%seen_text(ab,k1))
	expect(srv_wheat(ALPHA)==FULL and wheat(alpha)==FULL,"case 1 alpha wheat 999999999 (server %d, client %d)"%[srv_wheat(ALPHA),wheat(alpha)])
	var h0:=srv_harvests(ALPHA)
	expect(h0>=0,"case 1 server alpha.harvests readable (%d)"%h0)
	expect(not beta.other(alpha_public).is_empty() and not beta.other(alpha_public).has("inventory"),"case 1 beta sees alpha's player entry without an inventory")

	# 2. Harvest at capacity: refused, nothing changes anywhere.
	await settle(ab)
	var srv_before:=row_of(srv_crop(k1))
	var bn0:=beta.notices.size()
	var r1:=await act(alpha,"harvest",plot)
	print("%s case 2 reply %s"%[TAG,str(r1)])
	expect(r1.replied and not r1.ok and str(r1.message).contains(CAP_MARK),"case 2 alpha receives a refusal containing '%s' (got replied=%s ok=%s '%s')"%[CAP_MARK,str(r1.replied),str(r1.ok),str(r1.message)])
	await settle(ab)
	expect(beta.notices.size()==bn0,"case 2 beta gets no notice from alpha's harvest")
	var sc:=srv_crop(k1)
	expect(str(sc.get("kind",""))=="wheat" and float(sc.get("growth",-1.0))>=float(World.CROPS.wheat.time),"case 2 server crop still ripe wheat (%s)"%row_of(sc))
	expect(row_of(sc)==srv_before and row_of(sc)==ripe_row,"case 2 server crop kind/growth/remaining/wet unchanged (%s -> %s)"%[srv_before,row_of(sc)])
	expect(srv_wheat(ALPHA)==FULL,"case 2 server alpha wheat still 999999999 (got %d)"%srv_wheat(ALPHA))
	expect(srv_harvests(ALPHA)==h0,"case 2 server alpha.harvests unchanged (%d -> %d)"%[h0,srv_harvests(ALPHA)])
	expect(row_of(alpha.crop(k1))==ripe_row and wheat(alpha)==FULL,"case 2 alpha's snapshot: same unharvested crop %s and wheat %d"%[row_of(alpha.crop(k1)),wheat(alpha)])
	var bc:=beta.crop(k1)
	expect(str(bc.get("kind",""))==str(sc.get("kind","?")) and float(bc.get("growth",-1.0))==float(sc.get("growth",-2.0)),"case 2 beta's snapshot crop kind/growth equals the server (%s vs %s)"%[row_of(bc),row_of(sc)])
	expect(row_of(bc)==row_of(sc),"case 2 beta's snapshot crop row equals the server")
	expect(not beta.other(alpha_public).has("inventory") and not JSON.stringify(beta.session.snapshot).contains(str(FULL)),"case 2 beta does not see alpha's inventory (no 999999999 anywhere in beta's snapshot)")

	# 3. Make room (live preset), harvest again with a fresh sequence: success.
	var live_inv=srv_player(ALPHA).get("inventory",null)
	if not expect(live_inv is Dictionary,"case 3 server alpha inventory present"):return false
	preset(live_inv,"wheat",ROOM) # PRESET 8 live: alpha now holds 999999998 wheat
	var seq1:int=int(r1.sequence)
	var r2:=await act(alpha,"harvest",plot)
	print("%s case 3 reply %s"%[TAG,str(r2)])
	expect(int(r2.sequence)>seq1,"case 3 second harvest used a fresh sequence (%d > %d)"%[int(r2.sequence),seq1])
	expect(r2.replied and r2.ok and str(r2.message).begins_with("收成了！"),"case 3 alpha receives success (got replied=%s ok=%s '%s')"%[str(r2.replied),str(r2.ok),str(r2.message)])
	await settle(ab)
	expect(srv_wheat(ALPHA)==CAP,"case 3 server alpha wheat == 1000000000 (got %d)"%srv_wheat(ALPHA))
	expect(srv_harvests(ALPHA)==h0+1,"case 3 server alpha.harvests +1 (%d -> %d)"%[h0,srv_harvests(ALPHA)])
	expect(await all_see(ab,k1,empty_row,3.0),"case 3 server, alpha and beta all see the cleared plot %s"%seen_text(ab,k1))
	expect(await wait_until(func():return wheat(alpha)==CAP,3.0),"case 3 alpha's snapshot wheat == 1000000000 (got %d)"%wheat(alpha))
	expect(not beta.other(alpha_public).is_empty() and not beta.other(alpha_public).has("inventory"),"case 3 beta still does not see alpha's inventory")

	expect(disk_wheat(read_disk(),ALPHA)==CAP,"capacity award persisted before contention fixture reset")
	if not await harvest_contention():return false
	var final_alpha:=srv_wheat(ALPHA)
	var final_beta:=srv_wheat(BETA)

	# 4. Normal shutdown, then the on-disk save.
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	await pause(0.3)
	var last_row:=row_of(srv_crop(k1))
	expect(await stop_server(),"case 4 server shuts down with a final save")
	var disk=read_disk()
	if not expect(disk is Dictionary,"case 4 save parses"):return false
	expect(disk_valid(disk),"case 4 saved world passes SaveSchema")
	expect(disk_wheat(disk,ALPHA)==final_alpha and disk_wheat(disk,BETA)==final_beta,"case 4 save holds both final wheat totals")
	expect(disk_row(disk_crop(disk,k1))==last_row and last_row==empty_row,"case 4 save: plot cleared as on the server (disk %s, server %s)"%[disk_row(disk_crop(disk,k1)),last_row])
	return true

func harvest_contention()->bool:
	var rounds:=100
	var ripe:=srv_crop(k1).duplicate(true)
	ripe.merge({"kind":"wheat","growth":float(World.CROPS.wheat.time),"remaining":1,"harvest_access":"island"},true)
	preset(srv_player(ALPHA).inventory,"wheat",0)
	var initial_total:=srv_wheat(ALPHA)+srv_wheat(BETA)
	var wins:=[0,0]
	for index in rounds:
		preset(server.world.state.crops,k1,ripe.duplicate(true))
		var before:=[srv_wheat(ALPHA),srv_wheat(BETA)]
		var marks:=[alpha.notices.size(),beta.notices.size()]
		var first:=alpha if index%2==0 else beta
		var second:=beta if first==alpha else alpha
		for client in [first,second]:
			var sequence:int=client.session.perform("harvest",plot)
			var snapshot:Dictionary=client.session.snapshot
			client.session.request_action.rpc_id(1,sequence,"harvest",plot,"",str(snapshot.region_id),int(client.me().get("travel_epoch",0)))
		if not expect(await wait_until(func():return alpha.notices.size()>marks[0] and beta.notices.size()>marks[1],3.0),"round %d both peers receive an answer"%index):return false
		var alpha_won:bool=alpha.notices[marks[0]][1]
		var beta_won:bool=beta.notices[marks[1]][1]
		expect(alpha_won!=beta_won,"round %d exactly one winner"%index)
		wins[0]+=int(alpha_won)
		wins[1]+=int(beta_won)
		expect(srv_wheat(ALPHA)==before[0]+2*int(alpha_won) and srv_wheat(BETA)==before[1]+2*int(beta_won),"round %d one exact harvest payout"%index)
		expect(srv_crop(k1).get("kind","missing")=="","round %d plot spent"%index)
		# Keep below the rolling rate cap and let exact-sequence replays arrive.
		await pause(0.105)
		expect(alpha.notices.size()==marks[0]+1 and beta.notices.size()==marks[1]+1,"round %d duplicate sequences never reach harvest handling"%index)
	expect(wins[0]+wins[1]==rounds and srv_wheat(ALPHA)+srv_wheat(BETA)==initial_total+2*rounds,"100 ripe plants pay exactly 200 wheat")
	expect(await wait_until(func():return wheat(alpha)==srv_wheat(ALPHA) and wheat(beta)==srv_wheat(BETA) and alpha.crop(k1).get("kind","missing")=="" and beta.crop(k1).get("kind","missing")=="",3.0),"both clients see their final wheat totals and the same spent plot")
	print("%s contention_rounds=%d wins=%s"%[TAG,rounds,wins])
	return true

func teardown()->void:
	for c in [alpha,beta]:
		if c!=null and is_instance_valid(c.session) and not c.session.shutting_down:
			c.session.shutdown()
	await pause(0.2)
	if server!=null and is_instance_valid(server) and server.world!=null:
		expect(server.shutdown(),"final server shutdown saves cleanly")
	await pause(0.2)
	for c in [alpha,beta]:
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
