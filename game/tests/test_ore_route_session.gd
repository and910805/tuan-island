extends SceneTree
## 第 40 章金瓜石初訪「運礦路線」two-client Session acceptance over a real dedicated server and
## real WebSocket clients (modelled on test_gold_panning_session.gd).
##
## LEVEL: one machine, ONE Godot process. A dedicated server Session listens on a free
## 127.0.0.1 port (websocket transport); two client Sessions (alpha, beta, both in 金瓜石 next to
## the load platform Route.STOPS[0]) and later a late joiner (gamma, joins at home) connect over
## loopback, each in its own branch with its own SceneMultiplayer. Clients only read their own
## received snapshots. The on-disk save is read (file only) after shutdowns. Same-machine,
## single-process evidence only.
##
## SEEDED FIXTURE (disclosed): built offline in a World before the server starts and validated
## with SaveSchema. WRITTEN directly: alpha and beta are fresh players whose region is set to
## "jinguashi" and whose x/y are set to standable cells within Route.REACH of the load platform
## (found with World.can_stand in the Jinguashi layer); receipts cleared. Nothing is EARNED
## offline: no ore_route key is preset, nobody travelled there. Coins are the add_player
## defaults (read back from the first snapshot, not assumed).
## DIRECT WRITES ON THE RUNNING SERVER WORLD (disclosed): unlike the panning template, the cart
## moves along the track, so before every cart request the test writes the actor's x/y in
## server.world.state.players[token] to a precomputed standable cell within REACH of the cart's
## current stop (nobody walks over the network; clients never send movement). For the late
## joiner the test also writes region="jinguashi" (+ x/y) on the server world instead of
## travelling. World time starts at 0 (day 1) and only advances by real-time server ticks; the
## test never advances it (every cart happens on day 1).
## PLAYED over the network: every ore_cart step (load / push / unload) of alpha, beta and gamma,
## through Session.perform → request_action; all refusals likewise.
## Replay: the raw request_action RPC re-sent with an already-used sequence number (load, push,
## unload, with extras/cells that WOULD succeed if processed); Session drops it.
##
## KNOWN LEAKS (not asserted away): coins are public player data, so a watcher can see another
## player's purse grow by Route.PAY when a cart is unloaded (i.e. that a delivery finished, not
## the mid-route stage). Player x/y are public too; here they are test-written next to the cart,
## so position hints at where the cart stands. The "not derivable" check therefore compares the
## other player's public record with x/y (and, for unload, coins) removed.
## NOT covered: multiple processes, TLS, latency/loss, crash durability (normal shutdowns only),
## day rollover of the daily count, PURSE_FULL (rule level, test_ore_route.gd), real walking
## along the track, travelling into or out of Jinguashi over the network, UI/page buttons.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Route=preload("res://scripts/ore_route.gd")
const KEY:="ore-route-session"
const ALPHA:="oreroute-session-alpha-token"
const BETA:="oreroute-session-beta-token"
const GAMMA:="oreroute-session-gamma-token"

class Client:
	var label:=""
	var token:=""
	var slot:=0
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
	func own()->Variant:
		return session.snapshot.get(Route.OWN_KEY,null)
	func coins()->int:
		return int(me().get("coins",-1))

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
## stop_spots[i] = standable positions (cell centres) within reach of Route.STOPS[i], nearest first.
var stop_spots:Array=[]

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)
	return ok

func _initialize()->void:
	create_timer(115.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("ORE_ROUTE_SESSION watchdog fired before completion")
	print("ORE_ROUTE_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("ORE_ROUTE_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("ORE_ROUTE_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("ORE_ROUTE_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

func place(w:World,token:String,region:String,at:Vector2)->void:
	var p:Dictionary=w.state.players[token]
	p["region"]=region
	p["x"]=at.x
	p["y"]=at.y

## Standable positions (cell centres) within reach of every stop, nearest first.
func find_stop_spots(w:World)->Array:
	var all:Array=[]
	w.switch_region(Route.REGION)
	for stop:Vector2i in Route.STOPS:
		var centre:=Vector2(stop)+Vector2(0.5,0.5)
		var out:Array=[]
		for dy in range(-2,3):
			for dx in range(-2,3):
				var pos:=Vector2(stop.x+dx,stop.y+dy)+Vector2(0.5,0.5)
				if pos.distance_to(centre)>Route.REACH-0.4:continue
				if w.can_stand(pos):out.append(pos)
		out.sort_custom(func(a:Vector2,b:Vector2):return a.distance_to(centre)<b.distance_to(centre))
		all.append(out)
	w.switch_region("home")
	return all

func seed_world(path:String)->bool:
	var w:=World.new()
	w.add_player(ALPHA,"alpha")
	w.add_player(BETA,"beta")
	stop_spots=find_stop_spots(w)
	for i in stop_spots.size():
		if (stop_spots[i] as Array).is_empty():
			push_error("no standable cell within reach of stop %d %s"%[i,str(Route.STOPS[i])])
			return false
	place(w,ALPHA,Route.REGION,spot(0,0))
	place(w,BETA,Route.REGION,spot(0,1))
	for token in [ALPHA,BETA]:
		w.state.players[token]["receipts"]={}
	w.active_tokens.clear()
	w.save_path=path
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.has(Route.STATE_KEY) or float(parsed.time)+300.0>=1440.0:return false
	return Schema.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func spot(stop_index:int,slot:int)->Vector2:
	var spots:Array=stop_spots[stop_index]
	return spots[mini(slot,spots.size()-1)]

## DIRECT WRITE on the running server World: put `c` next to the cart cell of `at_stage`.
func stand(c:Client,at_stage:int)->void:
	var at:=spot(clampi(at_stage,1,Route.LAST)-1,c.slot)
	var p:Dictionary=server.world.state.players[c.token]
	p["x"]=at.x
	p["y"]=at.y

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

func join(label:String,token:String,slot:int,port:int)->Client:
	var c:=Client.new()
	c.label=label
	c.token=token
	c.slot=slot
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

# ---------------------------------------------------------------- helpers --

static func text(d:Variant)->String:
	return JSON.stringify(d,"",true)

static func view(stage:int,count:int,total:int)->String:
	return text({"stage":stage,"count":count,"total":total})

func own_text(c:Client)->String:
	return text(c.own())

func region_of(c:Client)->String:
	return str(c.session.snapshot.get("region_id",""))

## Own route view and coins, as text.
func marks_of(clients:Array)->Array:
	return clients.map(func(x):return [text(x.own()),x.coins()])

## `token`'s public player record as `watcher` receives it, minus the test-written x/y
## (and coins when `drop_coins`, the disclosed unload leak).
func seen(watcher:Client,token:String,drop_coins:bool=false)->String:
	var people=watcher.session.snapshot.get("players",{})
	if not people is Dictionary:return "<no players>"
	var person=people.get(token.sha256_text().left(16))
	if not person is Dictionary:return "<absent>"
	var d:Dictionary=(person as Dictionary).duplicate(true)
	d.erase("x")
	d.erase("y")
	if drop_coins:d.erase("coins")
	return text(d)

## Every dictionary key anywhere in `v` whose name mentions the route or the cart action.
static func route_keys(v:Variant,out:Array)->void:
	if v is Dictionary:
		for k in v:
			var key_name:=str(k)
			if key_name.contains(Route.STATE_KEY) or key_name.contains(Route.ACTION):out.append(key_name)
			route_keys(v[k],out)
	elif v is Array:
		for x in v:route_keys(x,out)

static func push_message(from_stage:int)->String:
	return Route.PUSH_LAST if from_stage+1==Route.LAST else Route.PUSH_OK%[from_stage,Route.LAST-(from_stage+1)]

## One cart step over the wire: the test writes the actor next to the cart, then performs.
func drive(c:Client,from_stage:int,step:String,message:String,label:String,watchers:Array)->Dictionary:
	stand(c,from_stage)
	var r:=await act(c,Route.ACTION,Route.cart_cell(from_stage),step)
	expect(r.replied and r.ok and str(r.message)==message,"%s: ok with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle([c]+watchers)
	return r

## A push by `c` while each watcher's view of c's public record (minus x/y) must not move.
func blind_push(c:Client,from_stage:int,label:String,watchers:Array)->Dictionary:
	await settle([c]+watchers)
	var before:Array=watchers.map(func(w):return seen(w,c.token))
	var r:=await drive(c,from_stage,"push",push_message(from_stage),label,watchers)
	expect(watchers.map(func(w):return seen(w,c.token))==before,"%s: watchers' view of %s's public record (minus x/y) unchanged by the push"%[label,c.label])
	return r

func refuse(c:Client,step:String,p:Vector2i,message:String,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var marks:=marks_of(everyone)
	var r:=await act(c,Route.ACTION,p,step)
	expect(r.replied and not r.ok and str(r.message)==message,"%s: refused with '%s' (got replied=%s ok=%s '%s')"%[label,message,str(r.replied),str(r.ok),str(r.message)])
	await settle(everyone)
	expect(marks_of(everyone)==marks,"%s: own_ore_route and coins unchanged in every watching snapshot"%label)

## Raw re-send of an already-used sequence number: no notice anywhere, nothing changes.
func resend(c:Client,sequence:int,step:String,p:Vector2i,label:String,watchers:Array)->void:
	var everyone:Array=[c]+watchers
	await settle(everyone)
	var counts:Array=everyone.map(func(x):return x.notices.size())
	var before:=marks_of(everyone)
	c.session.request_action.rpc_id(1,sequence,Route.ACTION,p,step,region_of(c),int(c.me().get("travel_epoch",0)))
	await pause(0.6)
	await settle(everyone)
	expect(everyone.map(func(x):return x.notices.size())==counts,"%s: re-sent sequence %d ('%s') gets no notice"%[label,sequence,step])
	expect(marks_of(everyone)==before,"%s: re-sent sequence %d ('%s') changes nothing on any end"%[label,sequence,step])

## Privacy: no raw token, no ore_route key anywhere; the only route key is the recipient's
## own_ore_route (only in Jinguashi) with exactly stage/count/total.
func private_check(c:Client,in_jinguashi:bool,label:String)->void:
	var dump:=JSON.stringify(c.session.snapshot)
	var leaked:=false
	for t:String in [ALPHA,BETA,GAMMA]:
		if dump.contains(t):leaked=true
	expect(not leaked,"%s: %s's snapshot contains no raw token"%[label,c.label])
	expect(not c.session.snapshot.has(Route.STATE_KEY) and not dump.contains("\"%s\""%Route.STATE_KEY),"%s: %s's snapshot has no '%s' key anywhere"%[label,c.label,Route.STATE_KEY])
	var found:Array=[]
	route_keys(c.session.snapshot,found)
	var want:Array=[Route.OWN_KEY] if in_jinguashi else []
	expect(found==want,"%s: %s's only route keys are %s (got %s)"%[label,c.label,str(want),str(found)])
	if in_jinguashi:
		var o=c.own()
		var keys:Array=[]
		if o is Dictionary:
			for k in o:keys.append(str(k))
		keys.sort()
		expect(keys==["count","stage","total"],"%s: %s's own_ore_route has exactly stage/count/total (got %s)"%[label,c.label,str(keys)])

func read_disk()->Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(save_path))

func disk_valid(disk:Variant)->bool:
	return disk is Dictionary and Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

static func disk_record(disk:Variant,token:String)->String:
	if not disk is Dictionary:return "<no save>"
	var whole=disk.get(Route.STATE_KEY)
	if not whole is Dictionary or not whole.get("players") is Dictionary:return "<no record>"
	var own=whole.players.get(token)
	if not own is Dictionary:return "<no record>"
	var out:={}
	for field in own:out[str(field)]=int(own[field])
	return text(out)

static func disk_coins(disk:Variant,token:String)->int:
	if not disk is Dictionary or not disk.get("players") is Dictionary:return -1
	var person=disk.players.get(token)
	return int(person.get("coins",-1)) if person is Dictionary else -1

static func record(stage:int,day:int,count:int,total:int)->String:
	return text({"stage":stage,"day":day,"count":count,"total":total})

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("ore-route-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	save_path=folder.path_join("world.json")
	if not expect(seed_world(save_path),"SEEDED FIXTURE (alpha/beta written into Jinguashi beside the load platform; nothing earned; no ore_route) accepted by SaveSchema"):return false
	var port:=start_server()
	if not expect(port>0,"server Session hosts on 127.0.0.1 (websocket)"):return false
	alpha=await join("alpha",ALPHA,0,port)
	beta=await join("beta",BETA,1,port)
	if not expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback"):return false
	expect(server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer,"server and clients use WebSocketMultiplayerPeer")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World")
	await settle([alpha,beta])
	expect(region_of(alpha)==Route.REGION and region_of(beta)==Route.REGION,"alpha and beta are in 金瓜石 (%s / %s)"%[region_of(alpha),region_of(beta)])
	var coins_a:=alpha.coins()
	var coins_b:=beta.coins()
	expect(coins_a>=0 and coins_b>=0,"starting coins readable (alpha %d, beta %d)"%[coins_a,coins_b])
	print("ORE_ROUTE_SESSION_LABEL machine=single process=single transport=websocket loopback=127.0.0.1:%d clients=2(+late joiner) fixture=SEEDED(region+spot written; nothing earned) positions=DIRECT-WRITE(server world, per step) shutdown=normal-only"%port)

	# 1. Fresh: both see their own zero view; no server record anywhere.
	for c:Client in [alpha,beta]:
		expect(own_text(c)==view(0,0,0),"case 1 %s: own_ore_route is zeros (%s)"%[c.label,own_text(c)])
		expect(Route.next_step(c.session.snapshot)=="load" and Route.step_block(c.session.snapshot,"load",c.me())=="","case 1 %s's client helper: next step load, not blocked"%c.label)
		expect(Route.today(c.session.snapshot)==1,"case 1 %s: world day 1"%c.label)
		private_check(c,true,"case 1")

	# 2. Refusals at stage 0 leave both ends unchanged.
	var load_cell:Vector2i=Route.STOPS[0]
	stand(alpha,0)
	await refuse(alpha,"dig",load_cell,Route.BAD_EXTRA,"case 2 alpha unknown step",[beta])
	await refuse(alpha,"push",load_cell,Route.NEED_LOAD,"case 2 alpha pushes before loading",[beta])
	await refuse(alpha,"unload",load_cell,Route.NEED_LOAD,"case 2 alpha unloads an empty cart",[beta])
	await refuse(alpha,"load",Route.STOPS[1],Route.WRONG_CELL,"case 2 alpha loads on the first track stop",[beta])

	# 3. Alpha loads: only alpha's own view moves; replay and a second load change nothing.
	var a_st:=0
	var b_st:=0
	var loaded:=await drive(alpha,a_st,"load",Route.LOAD_OK,"case 3 alpha loads",[beta])
	a_st=1
	await wait_until(func():return own_text(alpha)==view(1,0,0),3.0)
	expect(own_text(alpha)==view(1,0,0),"case 3 alpha sees stage 1 (%s)"%own_text(alpha))
	expect(Route.next_step(alpha.session.snapshot)=="push","case 3 alpha's client helper: next push")
	expect(own_text(beta)==view(0,0,0),"case 3 beta's own view stays zeros (%s)"%own_text(beta))
	await resend(alpha,int(loaded.sequence),"push",Route.cart_cell(1),"case 3 load sequence as push",[beta])
	await resend(alpha,int(loaded.sequence),"load",Route.cart_cell(1),"case 3 load sequence as load",[beta])
	expect(own_text(alpha)==view(1,0,0),"case 3 alpha still at stage 1 after the replays")
	await refuse(alpha,"load",Route.cart_cell(1),Route.LOADED,"case 3 alpha loads a loaded cart",[beta])
	for c:Client in [alpha,beta]:private_check(c,true,"case 3")

	# 4. Interleaved carts: alpha pushes 3, beta loads and pushes 1, then refusals.
	for i in 3:
		await blind_push(alpha,a_st,"case 4 alpha push from stage %d"%a_st,[beta])
		a_st+=1
		await wait_until(func():return own_text(alpha)==view(a_st,0,0),3.0)
		expect(own_text(alpha)==view(a_st,0,0) and own_text(beta)==view(0,0,0),"case 4 alpha %s / beta zeros (got %s / %s)"%[view(a_st,0,0),own_text(alpha),own_text(beta)])
	await drive(beta,b_st,"load",Route.LOAD_OK,"case 4 beta loads",[alpha])
	b_st=1
	var beta_push:=await blind_push(beta,b_st,"case 4 beta push from stage 1",[alpha])
	b_st=2
	await wait_until(func():return own_text(beta)==view(2,0,0),3.0)
	expect(own_text(alpha)==view(4,0,0) and own_text(beta)==view(2,0,0),"case 4 after interleave: alpha stage 4 / beta stage 2 (got %s / %s)"%[own_text(alpha),own_text(beta)])
	expect(Route.cart_cell(a_st)==Route.STOPS[3],"case 4 alpha's cart is at stop 3")
	# Wrong order / wrong cell / too far / someone else's cart: all refused, both ends unchanged.
	stand(alpha,a_st)
	await refuse(alpha,"unload",Route.cart_cell(a_st),Route.NOT_THERE,"case 4 alpha unloads mid-route",[beta])
	await refuse(alpha,"load",load_cell,Route.WRONG_CELL,"case 4 alpha acts on the load cell while her cart is at stop 3",[beta])
	await refuse(alpha,"push",load_cell,Route.WRONG_CELL,"case 4 alpha pushes on the load cell while her cart is at stop 3",[beta])
	await refuse(alpha,"push",Route.cart_cell(a_st+1),Route.WRONG_CELL,"case 4 alpha pushes on the next stop instead of her cart",[beta])
	stand(alpha,0)
	await refuse(alpha,"push",Route.cart_cell(a_st),Route.TOO_FAR,"case 4 alpha (standing at the load platform) pushes her cart at stop 3",[beta])
	stand(alpha,a_st)
	stand(beta,b_st)
	await refuse(beta,"push",Route.cart_cell(a_st),Route.WRONG_CELL,"case 4 beta pushes on alpha's cart cell",[alpha])
	await resend(beta,int(beta_push.sequence),"push",Route.cart_cell(b_st),"case 4 beta's push sequence as push",[alpha])
	expect(own_text(alpha)==view(4,0,0) and own_text(beta)==view(2,0,0),"case 4 views unchanged after refusals and replay (%s / %s)"%[own_text(alpha),own_text(beta)])
	for c:Client in [alpha,beta]:private_check(c,true,"case 4")

	# 5. Beta pushes once more; alpha finishes cart 1 (pushes to the end, unloads, paid once).
	await blind_push(beta,b_st,"case 5 beta push from stage 2",[alpha])
	b_st=3
	var last_push:Dictionary={}
	while a_st<Route.LAST:
		last_push=await blind_push(alpha,a_st,"case 5 alpha push from stage %d"%a_st,[beta])
		a_st+=1
	await wait_until(func():return own_text(alpha)==view(Route.LAST,0,0),3.0)
	expect(own_text(alpha)==view(Route.LAST,0,0) and Route.next_step(alpha.session.snapshot)=="unload","case 5 alpha at the unload platform, next unload (%s)"%own_text(alpha))
	stand(alpha,a_st)
	await resend(alpha,int(last_push.sequence),"unload",Route.cart_cell(a_st),"case 5 last push sequence as unload",[beta])
	await refuse(alpha,"push",Route.cart_cell(a_st),Route.AT_END,"case 5 alpha pushes past the unload platform",[beta])
	expect(alpha.coins()==coins_a,"case 5 no pay before unloading (%d)"%alpha.coins())
	var unloaded:=await drive(alpha,a_st,"unload",Route.UNLOAD_OK%[Route.PAY,1],"case 5 alpha unloads cart 1",[beta])
	a_st=0
	await wait_until(func():return alpha.coins()==coins_a+Route.PAY and own_text(alpha)==view(0,1,1),3.0)
	expect(own_text(alpha)==view(0,1,1),"case 5 alpha's view {stage 0, count 1, total 1} (%s)"%own_text(alpha))
	expect(alpha.coins()==coins_a+Route.PAY,"case 5 alpha paid %d once (%d -> %d)"%[Route.PAY,coins_a,alpha.coins()])
	expect(own_text(beta)==view(3,0,0) and beta.coins()==coins_b,"case 5 beta unchanged (%s, coins %d)"%[own_text(beta),beta.coins()])
	await resend(alpha,int(unloaded.sequence),"unload",Route.cart_cell(Route.LAST),"case 5 unload sequence as unload",[beta])
	stand(alpha,0)
	await resend(alpha,int(unloaded.sequence),"load",load_cell,"case 5 unload sequence as load at the load platform",[beta])
	expect(alpha.coins()==coins_a+Route.PAY and own_text(alpha)==view(0,1,1),"case 5 replays paid nothing more and loaded no new cart")
	for c:Client in [alpha,beta]:private_check(c,true,"case 5")

	# 6. Alpha starts cart 2 and leaves it mid-route at stage 3.
	await drive(alpha,a_st,"load",Route.LOAD_OK,"case 6 alpha loads cart 2",[beta])
	a_st=1
	while a_st<3:
		await blind_push(alpha,a_st,"case 6 alpha push from stage %d"%a_st,[beta])
		a_st+=1
	await wait_until(func():return own_text(alpha)==view(3,1,1),3.0)
	expect(own_text(alpha)==view(3,1,1) and own_text(beta)==view(3,0,0),"case 6 alpha %s / beta %s"%[own_text(alpha),own_text(beta)])

	# 7. Reconnect, then a server restart: mid-route stages, counts and coins survive.
	await settle([alpha,beta])
	var before7:=marks_of([alpha,beta])
	await leave(alpha)
	alpha=null
	await pause(0.3)
	alpha=await join("alpha",ALPHA,0,port)
	if not expect(joined(alpha),"case 7 alpha reconnects"):return false
	await settle([alpha,beta])
	await wait_until(func():return alpha.own() is Dictionary,3.0)
	expect(marks_of([alpha,beta])==before7,"case 7 reconnect: own views and coins equal the pre-reconnect snapshots (%s vs %s)"%[str(marks_of([alpha,beta])),str(before7)])
	expect(own_text(alpha)==view(3,1,1),"case 7 reconnected alpha still at stage 3 (%s)"%own_text(alpha))
	await leave(alpha)
	await leave(beta)
	alpha=null
	beta=null
	expect(await stop_server(),"case 7 server shuts down with a final save")
	var disk=read_disk()
	if not expect(disk is Dictionary,"case 7 save parses"):return false
	expect(disk_valid(disk),"case 7 saved world passes SaveSchema")
	expect(Route.valid(disk.duplicate(true)),"case 7 OreRoute.valid accepts the saved record")
	var day:=Route.today(disk)
	expect(day==1,"case 7 save is still day 1 (%d)"%day)
	expect(disk_record(disk,ALPHA)==record(3,day,1,1),"case 7 save: alpha's record (%s)"%disk_record(disk,ALPHA))
	expect(disk_record(disk,BETA)==record(3,0,0,0),"case 7 save: beta's record (%s)"%disk_record(disk,BETA))
	expect(disk_record(disk,GAMMA)=="<no record>","case 7 save: gamma has no route record")
	expect(disk_coins(disk,ALPHA)==coins_a+Route.PAY and disk_coins(disk,BETA)==coins_b,"case 7 save: coins %d / %d"%[disk_coins(disk,ALPHA),disk_coins(disk,BETA)])
	var port2:=start_server()
	if not expect(port2>0,"case 7 restarted server hosts the same save"):return false
	alpha=await join("alpha",ALPHA,0,port2)
	beta=await join("beta",BETA,1,port2)
	if not expect(joined(alpha) and joined(beta),"case 7 both rejoin after the restart"):return false
	await settle([alpha,beta])
	await wait_until(func():return alpha.own() is Dictionary and beta.own() is Dictionary,3.0)
	expect(marks_of([alpha,beta])==before7,"case 7 restart: own views and coins equal the pre-restart snapshots (%s vs %s)"%[str(marks_of([alpha,beta])),str(before7)])
	for c:Client in [alpha,beta]:private_check(c,true,"case 7")

	# 8. Both resume where they stopped; alpha finishes cart 2, beta finishes cart 1.
	while a_st<Route.LAST:
		await blind_push(alpha,a_st,"case 8 alpha push from stage %d"%a_st,[beta])
		a_st+=1
	await drive(alpha,a_st,"unload",Route.UNLOAD_OK%[Route.PAY,2],"case 8 alpha unloads cart 2",[beta])
	a_st=0
	while b_st<Route.LAST:
		await blind_push(beta,b_st,"case 8 beta push from stage %d"%b_st,[alpha])
		b_st+=1
	await drive(beta,b_st,"unload",Route.UNLOAD_OK%[Route.PAY,1],"case 8 beta unloads cart 1",[alpha])
	b_st=0
	await wait_until(func():return own_text(alpha)==view(0,2,2) and own_text(beta)==view(0,1,1),3.0)
	expect(own_text(alpha)==view(0,2,2) and alpha.coins()==coins_a+2*Route.PAY,"case 8 alpha after cart 2 (%s, coins %d)"%[own_text(alpha),alpha.coins()])
	expect(own_text(beta)==view(0,1,1) and beta.coins()==coins_b+Route.PAY,"case 8 beta after cart 1 (%s, coins %d)"%[own_text(beta),beta.coins()])

	# 9. Daily limit: alpha's third cart on day 1 is refused; beta may still load.
	expect(Route.today(alpha.session.snapshot)==1,"case 9 still day 1 (time never advanced by the test)")
	expect(Route.step_block(alpha.session.snapshot,"load",alpha.me())==Route.DAILY_DONE,"case 9 alpha's client helper predicts DAILY_DONE")
	expect(Route.cart_label(alpha.session.snapshot)==Route.LABEL_FULL,"case 9 alpha's cart label says today is full")
	stand(alpha,0)
	await refuse(alpha,"load",load_cell,Route.DAILY_DONE,"case 9 alpha's third load",[beta])
	expect(Route.step_block(beta.session.snapshot,"load",beta.me())=="","case 9 beta may still load (her own count is 1)")
	for c:Client in [alpha,beta]:private_check(c,true,"case 9")

	# 10. Late joiner: at home no own_ore_route and refused; once (written) in Jinguashi, stage 0.
	gamma=await join("gamma",GAMMA,2,port2)
	if not expect(joined(gamma),"case 10 late joiner gamma joins"):return false
	await settle([alpha,beta,gamma])
	expect(region_of(gamma)=="home","case 10 gamma is at home (%s)"%region_of(gamma))
	expect(not gamma.session.snapshot.has(Route.OWN_KEY),"case 10 gamma's snapshot has no own_ore_route key")
	private_check(gamma,false,"case 10 home")
	await refuse(gamma,"load",load_cell,Route.WRONG_REGION,"case 10 gamma (at home) loads",[alpha,beta])
	await refuse(gamma,"push",Route.STOPS[3],Route.WRONG_REGION,"case 10 gamma (at home) pushes on alpha's old stop",[alpha,beta])
	server.world.state.players[GAMMA]["region"]=Route.REGION # DIRECT WRITE (disclosed): no travel
	stand(gamma,0)
	var arrived:=await wait_until(func():return region_of(gamma)==Route.REGION and gamma.own() is Dictionary,4.0)
	if not expect(arrived,"case 10 gamma's snapshot shows 金瓜石 with own_ore_route (%s)"%region_of(gamma)):return false
	expect(own_text(gamma)==view(0,0,0),"case 10 late joiner starts at stage 0 (%s)"%own_text(gamma))
	expect(Route.step_block(gamma.session.snapshot,"load",gamma.me())=="","case 10 gamma's client helper: may load")
	private_check(gamma,true,"case 10 jinguashi")
	await drive(gamma,0,"load",Route.LOAD_OK,"case 10 gamma loads her first cart",[alpha,beta])
	await wait_until(func():return own_text(gamma)==view(1,0,0),3.0)
	expect(own_text(gamma)==view(1,0,0),"case 10 gamma at stage 1 (%s)"%own_text(gamma))
	expect(own_text(alpha)==view(0,2,2) and own_text(beta)==view(0,1,1),"case 10 alpha/beta views unchanged by gamma (%s / %s)"%[own_text(alpha),own_text(beta)])
	for c:Client in [alpha,beta,gamma]:private_check(c,true,"case 10")
	await leave(gamma)
	await leave(alpha)
	await leave(beta)
	gamma=null
	alpha=null
	beta=null
	expect(await stop_server(),"case 10 restarted server shuts down cleanly")
	var after=read_disk()
	expect(disk_valid(after),"case 10 final save passes SaveSchema")
	var day2:int=Route.today(after) if after is Dictionary else -1
	expect(disk_record(after,ALPHA)==record(0,day2,2,2) and disk_record(after,BETA)==record(0,day2,1,1),"case 10 final save: alpha %s, beta %s"%[disk_record(after,ALPHA),disk_record(after,BETA)])
	expect(disk_record(after,GAMMA)==record(1,0,0,0),"case 10 final save: gamma %s"%disk_record(after,GAMMA))
	expect(disk_coins(after,ALPHA)==coins_a+2*Route.PAY and disk_coins(after,BETA)==coins_b+Route.PAY,"case 10 final save: coins %d / %d"%[disk_coins(after,ALPHA),disk_coins(after,BETA)])
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
