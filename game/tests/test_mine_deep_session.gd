extends SceneTree
## T067 deep mine (B6–B15) two-client Session verification: surface hoist, deep
## lift, same-node and commission races, disconnect/rejoin and restart persistence.
##
## LEVEL: one machine, ONE Godot process. Inside the single SceneTree a real
## dedicated server Session listens on a free 127.0.0.1 port with the WebSocket
## transport (WebSocketMultiplayerPeer) and separate client Session nodes join it
## over loopback. Every Session lives in its own branch with its own
## SceneMultiplayer (SceneTree.set_multiplayer(api, branch)), so RPC node paths
## are "Session" relative to each branch root on both sides; requests, notices
## and snapshots really travel through the RPC + WebSocket path. The clients
## only read their own received snapshots; the server World is not touched after
## seeding except for the on-disk save file read after the normal shutdown.
##
## SEEDED FIXTURE (disclosed, written to a fresh TEMP folder and validated with
## SaveSchema before use): picnic=true; mine_depths={unlocked:9, ready:{},
## pumped:24, hoist:false}; players alpha and beta stand on the jinguashi surface
## at the hoist arrival point beside the entry sign, each with reinforced_pick 1
## and the exact B9 commission materials (pump_kit 1, pipe_kit 4); alpha also
## holds the exact Q07 hoist repair parts (copper_joint 12, plank 4). Everything
## after the seed is performed through the client Sessions: the hoist repair,
## hoist rides, walking by real movement input, stairs, strikes, commissions, the
## deep lift, disconnects.
## Clock: real (no time scale). Durability: normal shutdown only (final save),
## not crash durability.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Mines=preload("res://scripts/mine_depths.gd")
const Catalog=preload("res://scripts/mine_expansion_catalog.gd")
const Regions=preload("res://scripts/regions.gd")
const KEY:="deep-mine-session"
const ALPHA:="deep-session-alpha-token"
const BETA:="deep-session-beta-token"
const GAMMA:="deep-session-gamma-token"
const SURFACE:="jinguashi"
const SURFACE_ARRIVAL:=Vector2(27.5,19.5)
const NODE:=Vector2i(20,20)
const LANE_Y:=19.5
const STRIKE_SPOT:=Vector2(19.0,19.5)
const SERVICE_SPOT:=Vector2(35.5,19.5)

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
	func unlocked()->int:
		return int(session.snapshot.get("mine_depths",{}).get("unlocked",0))
	func visible_ids()->Array:
		var ids:Array=session.snapshot.get("players",{}).keys()
		ids.sort()
		return ids

var checks:=0
var failures:=0
var serial:=0
var folder:=""
var save_path:=""
var server
var server_branch:Node
var finished:=false

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)

func _initialize()->void:
	create_timer(105.0).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("MINE_DEEP_SESSION watchdog fired before completion")
	print("MINE_DEEP_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:
		expect(remove_folder(),"temp fixture folder removed")
	else:
		print("MINE_DEEP_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("MINE_DEEP_SESSION duration_ms=%d"%(Time.get_ticks_msec()-started))
	print("MINE_DEEP_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

# ---------------------------------------------------------------- fixture --

func seed_fixture()->bool:
	folder=OS.get_environment("TEMP").path_join("mine-deep-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if DirAccess.make_dir_recursive_absolute(folder)!=OK:return false
	save_path=folder.path_join("world.json")
	var w:=World.new()
	w.save_path=save_path
	w.state["picnic"]=true
	w.state["mine_depths"]={"unlocked":9,"ready":{},"pumped":24,"hoist":false}
	w.switch_region(SURFACE)
	var spot:=w.safe_arrival(SURFACE_ARRIVAL)
	w.switch_region(Regions.HOME)
	if spot==Vector2.ZERO:return false
	for token in [ALPHA,BETA]:
		w.add_player(token,"alpha" if token==ALPHA else "beta")
		var p:Dictionary=w.state.players[token]
		p["region"]=SURFACE
		p["x"]=spot.x
		p["y"]=spot.y
		var inv:Dictionary=p["inventory"]
		inv["reinforced_pick"]=1
		inv["pump_kit"]=1
		inv["pipe_kit"]=4
		if token==ALPHA:
			for item in Mines.HOIST_COST:inv[item]=int(Mines.HOIST_COST[item])
	w.active_tokens.clear()
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	return parsed is Dictionary and Schema.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

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
	await wait_until(func():return not c.session.own_id.is_empty() and not c.me().is_empty(),8.0)
	return c

func joined(c:Client)->bool:
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty()

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
	await create_timer(seconds).timeout

## Waits for two more snapshots on each client (they stream every 0.1 s and
## are also pushed right after every action).
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

## Both clients send the same request in the same frame.
func race(a:Client,b:Client,action:String,p:Vector2i,extra:String="")->Array:
	var na:=a.notices.size()
	var nb:=b.notices.size()
	a.session.perform(action,p,extra)
	b.session.perform(action,p,extra)
	var both:=await wait_until(func():return a.notices.size()>na and b.notices.size()>nb,4.0)
	if not both:return []
	await settle([a,b])
	return [bool(a.notices[na][1]),bool(b.notices[nb][1])]

## Steers every client through its waypoints with real movement input.
func walk(routes:Array,seconds:float=14.0)->bool:
	var index:Array=[]
	for route in routes:index.append(0)
	var deadline:=Time.get_ticks_msec()+int(seconds*1000.0)
	var done:=false
	while Time.get_ticks_msec()<deadline and not done:
		done=true
		for i in routes.size():
			var c:Client=routes[i][0]
			var points:Array=routes[i][1]
			if int(index[i])>=points.size():continue
			var last:=int(index[i])==points.size()-1
			var delta:Vector2=points[index[i]]-c.pos()
			if delta.length()<(0.3 if last else 0.6):
				index[i]=int(index[i])+1
				if int(index[i])>=points.size():
					c.session.input_direction(Vector2.ZERO)
					continue
				last=int(index[i])==points.size()-1
				delta=points[index[i]]-c.pos()
			done=false
			c.session.input_direction(delta.limit_length() if last else delta.normalized())
		if not done:await create_timer(0.05).timeout
	for route in routes:route[0].session.input_direction(Vector2.ZERO)
	await pause(0.5)
	await settle(routes.map(func(r):return r[0]))
	for i in routes.size():
		if int(index[i])<(routes[i][1] as Array).size():return false
	return true

func lane_route(c:Client,target:Vector2)->Array:
	return [c,[Vector2(c.pos().x,LANE_Y),Vector2(target.x,LANE_Y),target]]

static func cell_center(p:Vector2i)->Vector2:
	return Vector2(p)+Vector2(0.5,0.5)

static func ints(d:Dictionary)->Dictionary:
	var out:={}
	for k in d:out[str(k)]=int(d[k])
	return out

func delta_of(after:Dictionary,before:Dictionary)->Dictionary:
	var out:={}
	var a:=ints(after)
	var b:=ints(before)
	for k in a:
		if int(a[k])!=int(b.get(k,0)):out[k]=int(a[k])-int(b.get(k,0))
	for k in b:
		if not a.has(k) and int(b[k])!=0:out[k]=-int(b[k])
	return out

func expected_strike(depth:int)->Dictionary:
	var out:={}
	out[Mines.ORES[depth-1]]=int(Mines.YIELDS[depth-1])
	for found in Mines.finds(depth):out[found]=int(out.get(found,0))+1
	return out

func view(c:Client)->Dictionary:
	var p:=c.me()
	return {"region":c.region(),"x":float(p.get("x",0)),"y":float(p.get("y",0)),
		"inventory":ints(c.bag()),"coins":int(p.get("coins",-1)),"energy":int(p.get("mine_energy",-1))}

func same_view(a:Dictionary,b:Dictionary)->bool:
	return a.region==b.region and absf(a.x-b.x)<0.001 and absf(a.y-b.y)<0.001 and a.inventory==b.inventory and a.coins==b.coins

# --------------------------------------------------------------- scenario --

var alpha:Client
var beta:Client
var gamma:Client

func scenario()->bool:
	expect(seed_fixture(),"SEEDED FIXTURE written to TEMP and accepted by SaveSchema.validate")
	if save_path.is_empty() or not FileAccess.file_exists(save_path):return false
	var port:=start_server()
	expect(port>0,"server Session hosts on 127.0.0.1 with the websocket transport")
	if port==0:return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	expect(joined(alpha) and joined(beta),"alpha and beta joined over loopback and received their own snapshot")
	if not joined(alpha) or not joined(beta):return false
	var ws:bool=server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and beta.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer
	expect(ws,"server and both clients use WebSocketMultiplayerPeer")
	expect(server.multiplayer.is_server() and not alpha.session.multiplayer.is_server() and not beta.session.multiplayer.is_server(),"one server, two remote clients")
	expect(alpha.session.multiplayer.get_unique_id()!=1 and beta.session.multiplayer.get_unique_id()!=1 and alpha.session.multiplayer.get_unique_id()!=beta.session.multiplayer.get_unique_id(),"clients hold distinct non-server peer ids")
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World (snapshots only)")
	expect(alpha.session.own_id!=beta.session.own_id,"distinct tokens give distinct public ids")
	print("MINE_DEEP_SESSION_LABEL machine=single process=single transport=%s loopback=127.0.0.1:%d clients=2(+1 late joiner) fixture=SEEDED(unlocked=9,pumped=24,surface positions,picks,B9 commission kits) clock=real shutdown=normal-only(not crash durability)"%["websocket" if ws else "UNEXPECTED",port])

	# 1. seeded depth + surface hoist landings.
	for c in [alpha,beta]:
		expect(c.region()==SURFACE,"%s starts on the jinguashi surface (seeded)"%c.label)
		expect(c.unlocked()==9,"%s snapshot carries the seeded unlocked depth 9 (got %d)"%[c.label,c.unlocked()])
		expect(Mines.lift_targets(c.unlocked())==[6],"%s: hoist offers only landing B6 at unlocked 9"%c.label)
		expect(c.pos().distance_to(cell_center(Mines.ENTRY))<=3.2,"%s stands within reach of the entry sign"%c.label)
	var epoch_a:=int(alpha.me().get("travel_epoch",-1))
	var refused:=await act(alpha,"mine_travel",Mines.ENTRY,"mine_10")
	expect(refused.replied and not refused.ok,"hoist to B10 refused while unlocked<10")
	expect(alpha.region()==SURFACE and int(alpha.me().travel_epoch)==epoch_a,"refused B10 hoist leaves region/epoch unchanged")
	refused=await act(beta,"mine_travel",Mines.ENTRY,"mine_7")
	expect(refused.replied and not refused.ok and beta.region()==SURFACE,"B7 is not a hoist landing")
	refused=await act(beta,"mine_travel",Mines.ENTRY,"mine_15")
	expect(refused.replied and not refused.ok and beta.region()==SURFACE,"hoist to B15 refused while unlocked<15")

	# 1b. Q07: the surface hoist is stuck until one islander repairs it (shared).
	for c in [alpha,beta]:
		expect(c.session.snapshot.get("mine_depths",{}).get("hoist",null)==false,"%s snapshot carries hoist=false"%c.label)
	refused=await act(beta,"mine_travel",Mines.ENTRY,"mine_6")
	expect(refused.replied and not refused.ok and refused.message==World.HOIST_STUCK_MSG and beta.region()==SURFACE,"hoist to B6 is stuck before the repair (%s)"%refused.message)
	var beta_bag:=beta.bag().duplicate(true)
	refused=await act(beta,World.HOIST_ACTION,Mines.ENTRY)
	expect(refused.replied and not refused.ok and refused.message==World.HOIST_SHORT_MSG and delta_of(beta.bag(),beta_bag).is_empty(),"beta without parts cannot repair (%s)"%refused.message)
	var repair_bag:=alpha.bag().duplicate(true)
	var fixed:=await act(alpha,World.HOIST_ACTION,Mines.ENTRY)
	var repair_cost:={}
	for item in Mines.HOIST_COST:repair_cost[item]=-int(Mines.HOIST_COST[item])
	expect(fixed.ok and fixed.message==World.HOIST_OK_MSG and delta_of(alpha.bag(),repair_bag)==repair_cost,"alpha repairs the hoist paying exactly %s (got %s)"%[str(repair_cost),str(delta_of(alpha.bag(),repair_bag))])
	await settle([alpha,beta])
	expect(alpha.session.snapshot.mine_depths.get("hoist")==true and beta.session.snapshot.mine_depths.get("hoist")==true,"both snapshots see the repaired hoist")
	refused=await act(beta,World.HOIST_ACTION,Mines.ENTRY)
	expect(refused.replied and not refused.ok and refused.message==World.HOIST_DONE_MSG,"a second repair is refused (%s)"%refused.message)

	# 2. alpha rides to B6, beta stays: per-region snapshots.
	var bag_a:=alpha.bag().duplicate(true)
	var ride:=await act(alpha,"mine_travel",Mines.ENTRY,"mine_6")
	expect(ride.ok and alpha.region()=="mine_6","alpha rides the surface hoist to B6")
	expect(alpha.pos().distance_to(cell_center(Mines.LIFT))<=1.6,"alpha arrives beside the B6 lift cage (%s)"%str(alpha.pos()))
	expect(ints(alpha.bag())==ints(bag_a),"hoist ride costs nothing")
	await settle([beta])
	expect(beta.region()==SURFACE,"beta's snapshot stays on the surface")
	expect(alpha.visible_ids()==[alpha.session.own_id],"alpha on B6 sees only itself")
	expect(not beta.visible_ids().has(alpha.session.own_id),"beta on the surface does not see alpha on B6")
	expect(int(beta.session.snapshot.get("region_population",{}).get("mine_6",0))==1,"beta's room counts one islander on B6")
	ride=await act(beta,"mine_travel",Mines.ENTRY,"mine_6")
	expect(ride.ok and beta.region()=="mine_6","beta follows to B6")
	await settle([alpha,beta])
	var pair:=[alpha.session.own_id,beta.session.own_id]
	pair.sort()
	expect(alpha.visible_ids()==pair and beta.visible_ids()==pair,"on B6 both clients see each other")

	# 3. same-node race on B6.
	expect(await walk([[alpha,[Vector2(alpha.pos().x,LANE_Y),STRIKE_SPOT]],[beta,[Vector2(beta.pos().x,LANE_Y),STRIKE_SPOT]]]),"both walk to the B6 ore node by movement input")
	for c in [alpha,beta]:
		expect(c.pos().distance_to(cell_center(NODE))<=3.2,"%s within reach of node %s"%[c.label,str(NODE)])
	var before_a:=alpha.bag().duplicate(true)
	var before_b:=beta.bag().duplicate(true)
	var outcome:=await race(alpha,beta,"pick",NODE)
	expect(outcome.size()==2,"both strikes answered")
	if outcome.size()!=2:return false
	expect(int(outcome[0])+int(outcome[1])==1,"exactly one strike pays out (alpha=%s beta=%s)"%[outcome[0],outcome[1]])
	var payout:=expected_strike(6)
	var d_a:=delta_of(alpha.bag(),before_a)
	var d_b:=delta_of(beta.bag(),before_b)
	print("MINE_DEEP_SESSION node_race B6 winner=%s"%("alpha" if outcome[0] else "beta"))
	var winner_delta:Dictionary=d_a if outcome[0] else d_b
	var loser_delta:Dictionary=d_b if outcome[0] else d_a
	expect(winner_delta==payout,"winner gains exactly the B6 catalog payout %s (got %s)"%[str(payout),str(winner_delta)])
	expect(loser_delta.is_empty(),"refused striker's bag unchanged (got %s)"%str(loser_delta))
	var ore:String=Mines.ORES[5]
	expect(int(alpha.bag().get(ore,0))+int(beta.bag().get(ore,0))==int(before_a.get(ore,0))+int(before_b.get(ore,0))+int(Mines.YIELDS[5]),"ore totals conserved across both clients")
	for c in [alpha,beta]:
		expect(float(c.session.snapshot.mine_depths.ready.get("mine_6",{}).get("20,20",0.0))>0.0,"%s sees the B6 node cooldown"%c.label)

	# Stairs B6 -> B9 by movement input and DOWN.
	for depth in [6,7,8]:
		expect(await walk([lane_route(alpha,SERVICE_SPOT),lane_route(beta,SERVICE_SPOT)]),"both walk to the B%d stairs"%depth)
		var na:=await act(alpha,"mine_travel",Mines.DOWN,"mine_%d"%(depth+1))
		var nb:=await act(beta,"mine_travel",Mines.DOWN,"mine_%d"%(depth+1))
		expect(na.ok and nb.ok and alpha.region()=="mine_%d"%(depth+1) and beta.region()=="mine_%d"%(depth+1),"both take the stairs to B%d"%(depth+1))
		if not (na.ok and nb.ok):return false
	expect(await walk([lane_route(alpha,SERVICE_SPOT),lane_route(beta,SERVICE_SPOT)]),"both walk to the B9 service station")
	refused=await act(alpha,"mine_travel",Mines.DOWN,"mine_10")
	expect(refused.replied and not refused.ok and alpha.region()=="mine_9","B9 stairs down refused before the commission")

	# 4. commission race on B9.
	before_a=alpha.bag().duplicate(true)
	before_b=beta.bag().duplicate(true)
	outcome=await race(alpha,beta,"mine_commission",Mines.SERVICE)
	expect(outcome.size()==2,"both commissions answered")
	if outcome.size()!=2:return false
	expect(int(outcome[0])+int(outcome[1])==1,"commission settles exactly once (alpha=%s beta=%s)"%[outcome[0],outcome[1]])
	var cost:Dictionary=Catalog.COMMISSIONS[9].cost
	var spent:={}
	for item in cost:spent[item]=-int(cost[item])
	d_a=delta_of(alpha.bag(),before_a)
	d_b=delta_of(beta.bag(),before_b)
	var payer:Client=alpha if outcome[0] else beta
	var other:Client=beta if outcome[0] else alpha
	print("MINE_DEEP_SESSION commission_race B9 payer=%s hoist_rider=%s"%[payer.label,other.label])
	expect((d_a if outcome[0] else d_b)==spent,"payer %s consumed exactly %s"%[payer.label,str(spent)])
	expect((d_b if outcome[0] else d_a).is_empty(),"%s's materials untouched"%other.label)
	expect(alpha.unlocked()==10 and beta.unlocked()==10,"both clients see unlocked 10")
	# Replay the same request sequence from both clients, then a fresh retry.
	var marks:=[alpha.notices.size(),beta.notices.size()]
	for c in [alpha,beta]:
		c.session.request_action.rpc_id(1,c.session.counter,"mine_commission",Mines.SERVICE,"",c.region(),int(c.me().travel_epoch))
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==marks[0] and beta.notices.size()==marks[1],"replayed sequences are dropped silently")
	expect(alpha.unlocked()==10 and beta.unlocked()==10,"replay does not open another depth")
	var retry:=await act(other,"mine_commission",Mines.SERVICE)
	expect(retry.replied and not retry.ok,"a fresh retry after settlement is refused")
	expect(delta_of(alpha.bag(),before_a)==d_a and delta_of(beta.bag(),before_b)==d_b and other.unlocked()==10,"replay/retry consumed nothing more")

	# 6. deep lift: other client rides up from B9.
	refused=await act(other,"mine_travel",Mines.LIFT,SURFACE)
	expect(refused.replied and not refused.ok and other.region()=="mine_9","lift refused from across the floor (reach)")
	expect(await walk([[other,[Vector2(other.pos().x,LANE_Y),Vector2(17.5,LANE_Y),Vector2(17.5,18.5)]]]),"%s walks to the B9 lift"%other.label)
	for target in ["mine_10","mine_8","mine_6"]:
		refused=await act(other,"mine_travel",Mines.LIFT,target)
		expect(refused.replied and not refused.ok and other.region()=="mine_9","lift to %s refused (surface only)"%target)
	var lift_before:=view(other)
	ride=await act(other,"mine_travel",Mines.LIFT,SURFACE)
	expect(ride.ok and other.region()==SURFACE,"lift from B9 to the surface accepted")
	var lift_after:=view(other)
	expect(lift_after.inventory==lift_before.inventory and lift_after.coins==lift_before.coins,"deep lift is free (inventory and coins unchanged)")
	expect(other.pos().distance_to(cell_center(Mines.ENTRY))<=3.2,"lift arrives beside the surface entry sign")

	# 5. the non-paying client rides the hoist to the newly opened B10.
	expect(Mines.lift_targets(other.unlocked())==[6,10],"hoist now offers B6 and B10")
	ride=await act(other,"mine_travel",Mines.ENTRY,"mine_10")
	expect(ride.ok and other.region()=="mine_10","%s (did not pay) rides the hoist to B10"%other.label)
	var landing:=other.pos()
	var tile:=Vector2i(floori(landing.x),floori(landing.y))
	expect(landing.distance_to(cell_center(Mines.LIFT))<=1.6,"B10 arrival beside the lift (%s)"%str(landing))
	expect(World.land(tile,"mine_10") and not Regions.water(tile,"mine_10") and tile not in Mines.NODES,"B10 arrival on open land")
	refused=await act(other,"mine_travel",Mines.LIFT,"mine_9")
	expect(refused.replied and not refused.ok and other.region()=="mine_10","B10 lift to B9 refused")
	await settle([payer])
	expect(payer.region()=="mine_9" and not payer.visible_ids().has(other.session.own_id),"payer on B9 no longer sees the B10 rider")

	# 7. alpha disconnects on a deep floor; beta keeps acting; alpha rejoins.
	await pause(0.3)
	await settle([alpha,beta])
	var alpha_view:=view(alpha)
	expect(alpha_view.region in ["mine_9","mine_10"],"alpha is on a deep floor before disconnecting (%s)"%alpha_view.region)
	print("MINE_DEEP_SESSION disconnect alpha_on=%s beta_on=%s"%[alpha_view.region,beta.region()])
	await leave(alpha)
	expect(await wait_until(func():return int(beta.session.snapshot.get("room_population",0))==1,4.0),"server sees alpha leave (room population 1)")
	expect(await walk([lane_route(beta,STRIKE_SPOT)]),"beta walks to a node on %s"%beta.region())
	var depth_b:=Mines.depth_of(beta.region())
	before_b=beta.bag().duplicate(true)
	var strike:=await act(beta,"pick",NODE)
	expect(strike.ok and delta_of(beta.bag(),before_b)==expected_strike(depth_b),"beta strikes on B%d while alpha is away (payout %s)"%[depth_b,str(expected_strike(depth_b))])
	alpha=await join("alpha",ALPHA,port)
	expect(joined(alpha),"alpha rejoins with the same token")
	if not joined(alpha):return false
	expect(same_view(view(alpha),alpha_view),"alpha gets the same region/position/inventory/coins back (%s vs %s)"%[str(view(alpha)),str(alpha_view)])
	expect(alpha.unlocked()==10,"rejoined alpha sees unlocked 10")

	# 8. normal shutdown, save on disk, restart, rejoin, late joiner.
	await settle([alpha,beta])
	var final:={ALPHA:view(alpha),BETA:view(beta)}
	var ready_regions:Array=["mine_6",beta.region()]
	await leave(alpha)
	await leave(beta)
	expect(server.shutdown(),"server Session shuts down with a final save")
	await pause(0.2)
	server_branch.queue_free()
	var disk=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	expect(disk is Dictionary,"save file parses")
	if not disk is Dictionary:return false
	expect(Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"saved world passes SaveSchema")
	expect(int(disk.mine_depths.unlocked)==10 and int(disk.mine_depths.pumped)==24 and disk.mine_depths.get("hoist")==true,"save holds unlocked 10 and the repaired hoist")
	for region in ready_regions:
		expect(float(disk.mine_depths.ready.get(region,{}).get("20,20",0.0))>0.0,"save holds the %s node cooldown"%region)
	for token in [ALPHA,BETA]:
		var person:Dictionary=disk.players.get(token,{})
		var want:Dictionary=final[token]
		expect(str(person.get("region",""))==want.region and absf(float(person.get("x",0))-want.x)<0.001 and absf(float(person.get("y",0))-want.y)<0.001,"save holds %s's region/position %s"%[token.left(18),want.region])
		expect(ints(person.get("inventory",{}))==want.inventory and int(person.get("coins",-1))==want.coins,"save holds %s's inventory/coins"%token.left(18))
	var port2:=start_server()
	expect(port2>0,"a new server Session hosts the same save")
	if port2==0:return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	expect(joined(alpha) and joined(beta),"both clients rejoin the restarted server")
	if not joined(alpha) or not joined(beta):return false
	expect(same_view(view(alpha),final[ALPHA]),"alpha state identical after restart")
	expect(same_view(view(beta),final[BETA]),"beta state identical after restart")
	expect(alpha.unlocked()==10 and beta.unlocked()==10,"both see unlocked 10 after restart")
	for region in ready_regions:
		expect(beta.session.snapshot.mine_depths.ready.has(region),"restart snapshot keeps the %s cooldown record"%region)
	gamma=await join("gamma",GAMMA,port2)
	expect(joined(gamma),"late joiner gamma joins with a fresh token")
	if not joined(gamma):return false
	expect(gamma.region()==Regions.HOME,"gamma starts at home")
	expect(gamma.unlocked()==10 and Mines.lift_targets(gamma.unlocked())==[6,10],"gamma sees unlocked 10 and hoist landings B6/B10")
	expect(gamma.visible_ids()==[gamma.session.own_id],"gamma at home does not see the miners")
	expect(int(gamma.session.snapshot.get("room_population",0))==3,"room counts three islanders")
	refused=await act(gamma,"mine_travel",Mines.ENTRY,"mine_10")
	expect(refused.replied and not refused.ok and gamma.region()==Regions.HOME,"gamma cannot ride the hoist from home")
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
