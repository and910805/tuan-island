extends SceneTree
## T016 shared resource race, two real WebSocket clients: the same HOME tree,
## the same HOME rock and the public quarry are each raced by two islanders on
## their final hit. Exactly one drop is paid, the loser's bag is unchanged,
## both clients see the same shared state, and a restart on the same save
## cannot produce a second drop.
##
## LEVEL: one machine, ONE Godot process. Inside the single SceneTree a real
## dedicated server Session listens on a free 127.0.0.1 port with the WebSocket
## transport (WebSocketMultiplayerPeer) and two client Session nodes join it
## over loopback. Every Session lives in its own branch with its own
## SceneMultiplayer (SceneTree.set_multiplayer(api, branch)). Requests, notices
## and snapshots really travel through the RPC + WebSocket path. The clients
## only read their own received snapshots; the server World is not touched after
## seeding except for the on-disk save file read after the normal shutdown.
##
## RACE BARRIER: both clients call perform() in the same frame before either
## socket is polled again, so both requests are on the wire before the server
## answers either one. The server Session handles RPCs one at a time, so this
## proves that serialized competing requests pay one drop. It is ONE race per
## target, not the T088 100-race stress acceptance.
##
## SEEDED FIXTURE (disclosed; fresh World in a new TEMP folder, validated with
## SaveSchema before use). PRESET writes, nothing else:
##   state.board=true (the public quarry at (54,25) requires the repaired board);
##   alpha/beta x=34.5 y=26.5 in HOME (start position, within reach of tree
##   (33,28) and rock (35,25)).
## Inventories are the normal add_player starter bag. No damage/removed/quarry
## value is seeded: every hit, drop, removal and cooldown comes from requests.
## Clock: real (no time scale). Durability: normal shutdown only.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Regions=preload("res://scripts/regions.gd")
const TAG:="SHARED_RESOURCE_RACE_SESSION"
const KEY:="shared-resource-race-session"
const ALPHA:="resource-race-alpha-token"
const BETA:="resource-race-beta-token"
const TREE:=Vector2i(33,28)
const ROCK:=Vector2i(35,25)
const QUARRY:=Vector2i(54,25)
const WEST:=Vector2(34.5,26.5)
const EAST:=Vector2(52.5,25.5)
## Walking lane between the two spots at y=28.0 (feet span rows 27 and 28):
## rows 27 and 28 hold no tree/rock from x=34 to x=52 (plaza x35-45 and the
## x46-51 strip carry no resources; the nearest solids are the tree (33,28),
## the rock (40,26) and the tree (53,27), all off the lane). Every lane cell is
## re-checked with World.can_stand in the fixture.
const LANE_Y:=28.0
const TO_EAST:=[Vector2(34.5,LANE_Y),Vector2(52.5,LANE_Y),EAST]
const TO_WEST:=[Vector2(52.5,LANE_Y),Vector2(34.5,LANE_Y),WEST]
const TREE_DROP:={"wood":6,"fiber":2,"sapling":1,"resin":1}
const ROCK_DROP:={"stone":5}
const QUARRY_DROP:={"stone":6}
const TREE_WIN:="採集完成！木材 +6、纖維 +2、樹苗 +1、樹脂 +1"
const ROCK_WIN:="採集完成！石材 +5"
const QUARRY_WIN:="石材 +6！新的石層約 45 秒後就緒，可和朋友輪流採集"
const GONE:="這裡沒有可採集的資源"
const QUARRY_WAIT:="採石點正在露出新石層"

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
	func points()->int:
		return int(me().get("gathering_points",0))
	func epoch()->int:
		return int(me().get("travel_epoch",0))
	func removed()->Dictionary:
		var d=session.snapshot.get("removed",{})
		return d if d is Dictionary else {}
	func damage()->Dictionary:
		var d=session.snapshot.get("damage",{})
		return d if d is Dictionary else {}
	func quarry()->Dictionary:
		var d=session.snapshot.get("quarry",{})
		return d if d is Dictionary else {}
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
var alpha:Client
var beta:Client

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)

func _initialize()->void:
	create_timer(100.0).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("%s watchdog fired before completion"%TAG)
	print("%s_TESTS checks=%d failures=%d"%[TAG,checks,failures+1])
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
	print("%s_TESTS checks=%d failures=%d"%[TAG,checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

# ---------------------------------------------------------------- fixture --

static func tile(p:Vector2i)->String:
	return "%d,%d"%[p.x,p.y]

static func center(p:Vector2i)->Vector2:
	return Vector2(p)+Vector2(0.5,0.5)

func seed_fixture()->bool:
	folder=OS.get_environment("TEMP").path_join("shared-resource-race-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if DirAccess.make_dir_recursive_absolute(folder)!=OK:return false
	save_path=folder.path_join("world.json")
	var w:=World.new()
	w.save_path=save_path
	# Map facts the scenario relies on, checked against the real map code.
	expect(World.base_resource(TREE)=="tree" and World.base_resource(ROCK)=="rock","map: %s is a tree and %s is a rock"%[tile(TREE),tile(ROCK)])
	expect(not w.protected(TREE) and not w.protected(ROCK) and not w.water(TREE) and not w.water(ROCK),"map: tree and rock are neither protected nor water")
	expect(w.resource(TREE)=="tree" and w.resource(ROCK)=="rock" and w.state.removed.is_empty() and w.state.damage.is_empty(),"fresh World: targets standing, no removed/damage seeded")
	for spot in [WEST,EAST]+TO_EAST:
		expect(w.can_stand(spot),"map: %s is standable"%str(spot))
	var lane_clear:=true
	for step in 37:
		if not w.can_stand(Vector2(34.5+0.5*step,LANE_Y)):lane_clear=false
	for step in 6:
		if not w.can_stand(Vector2(52.5,LANE_Y-0.5*step)):lane_clear=false
	expect(lane_clear,"map: the whole walking lane (34.5..52.5, y=%.1f) and the climb to the quarry spot are standable"%LANE_Y)
	expect(WEST.distance_to(center(TREE))<=3.2 and WEST.distance_to(center(ROCK))<=3.2,"map: west spot reaches the tree and the rock")
	expect(EAST.distance_to(center(QUARRY))<=3.2,"map: east spot reaches the quarry")
	w.state["board"]=true # PRESET 1/2
	for token in [ALPHA,BETA]:
		w.add_player(token,"alpha" if token==ALPHA else "beta")
		var p:Dictionary=w.state.players[token]
		p["x"]=WEST.x # PRESET 2/2 (start position)
		p["y"]=WEST.y
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

## Network barrier: both clients send the same request in the same frame, then
## both replies are awaited. Returns [] if either reply is missing, else
## [{ok,message,sequence} alpha, {…} beta].
func race(a:Client,b:Client,action:String,p:Vector2i)->Array:
	var na:=a.notices.size()
	var nb:=b.notices.size()
	var sa:int=a.session.perform(action,p)
	var sb:int=b.session.perform(action,p)
	expect(sa>0 and sb>0 and a.notices.size()==na and b.notices.size()==nb,"%s race: both requests sent in one frame before any reply"%action)
	var both:=await wait_until(func():return a.notices.size()>na and b.notices.size()>nb,4.0)
	if not both:return []
	await settle([a,b])
	return [{"ok":bool(a.notices[na][1]),"message":str(a.notices[na][0]),"sequence":sa},
		{"ok":bool(b.notices[nb][1]),"message":str(b.notices[nb][0]),"sequence":sb}]

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

func view(c:Client)->Dictionary:
	var p:=c.me()
	return {"region":c.region(),"x":float(p.get("x",0)),"y":float(p.get("y",0)),
		"inventory":ints(c.bag()),"coins":int(p.get("coins",-1)),"points":c.points()}

func same_view(a:Dictionary,b:Dictionary)->bool:
	return a.region==b.region and absf(a.x-b.x)<0.001 and absf(a.y-b.y)<0.001 and a.inventory==b.inventory and a.coins==b.coins and a.points==b.points

## Replays `sequence` from `c` with matching region/epoch: the server must drop
## it silently (sequence already used) and nothing may change.
func replay(c:Client,sequence:int,action:String,p:Vector2i,label:String)->void:
	var marks:=[alpha.notices.size(),beta.notices.size()]
	var bags:=[ints(alpha.bag()),ints(beta.bag())]
	c.session.request_action.rpc_id(1,sequence,action,p,"",c.region(),c.epoch())
	await pause(0.6)
	await settle([alpha,beta])
	expect(alpha.notices.size()==marks[0] and beta.notices.size()==marks[1],"%s: replayed winning sequence %d dropped silently"%[label,sequence])
	expect(ints(alpha.bag())==bags[0] and ints(beta.bag())==bags[1],"%s: replay paid nothing"%label)

## Checks one final-hit race. `drop` is what the single winner must gain,
## `loser_prefix` the start of the loser's refusal, `gains_point` whether the
## winner earns one gathering point.
func judge(label:String,outcome:Array,before:Array,points_before:Array,win_msg:String,loser_prefix:String,drop:Dictionary,gains_point:bool)->int:
	expect(outcome.size()==2,"%s: both racers answered"%label)
	if outcome.size()!=2:return -1
	var oks:=[bool(outcome[0].ok),bool(outcome[1].ok)]
	expect(int(oks[0])+int(oks[1])==1,"%s: exactly one request succeeds (alpha=%s beta=%s)"%[label,oks[0],oks[1]])
	if int(oks[0])+int(oks[1])!=1:return -1
	var w:=0 if oks[0] else 1
	var l:=1-w
	var people:=[alpha,beta]
	print("%s %s winner=%s loser_message=%s"%[TAG,label,people[w].label,outcome[l].message])
	expect(str(outcome[w].message)==win_msg,"%s: winner message '%s'"%[label,outcome[w].message])
	expect(str(outcome[l].message).begins_with(loser_prefix),"%s: loser refused for the right reason '%s'"%[label,outcome[l].message])
	var dw:=delta_of(people[w].bag(),before[w])
	var dl:=delta_of(people[l].bag(),before[l])
	expect(dw==drop,"%s: winner gains exactly %s (got %s)"%[label,str(drop),str(dw)])
	expect(dl.is_empty(),"%s: loser bag unchanged, no tool or item spent (got %s)"%[label,str(dl)])
	for item in drop:
		var total:=int(alpha.bag().get(item,0))+int(beta.bag().get(item,0))
		var was:=int(before[0].get(item,0))+int(before[1].get(item,0))
		expect(total==was+int(drop[item]),"%s: %s total across both clients rose by exactly %d"%[label,item,int(drop[item])])
	expect(people[w].points()==int(points_before[w])+(1 if gains_point else 0),"%s: winner gathering points %+d"%[label,1 if gains_point else 0])
	expect(people[l].points()==int(points_before[l]),"%s: loser gathering points unchanged"%label)
	return w

# --------------------------------------------------------------- scenario --

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
	expect(alpha.session.world==null and beta.session.world==null,"client Sessions hold no World (snapshots only)")
	expect(alpha.session.own_id!=beta.session.own_id,"distinct tokens give distinct public ids")
	print("%s_LABEL machine=single process=single transport=%s loopback=127.0.0.1:%d clients=2 fixture=SEEDED(board=true, start x/y) presets=2 race=same-frame-send serialized-rpc clock=real shutdown=normal-only scope=one-race-per-target(not T088)"%[TAG,"websocket" if ws else "UNEXPECTED",port])
	for c in [alpha,beta]:
		expect(c.region()==Regions.HOME and c.pos().distance_to(WEST)<0.01,"%s starts at the seeded west spot"%c.label)
		expect(not c.removed().has(tile(TREE)) and not c.removed().has(tile(ROCK)) and not c.damage().has(tile(TREE)) and not c.damage().has(tile(ROCK)),"%s sees the tree and rock untouched"%c.label)

	# 1. Same tree: alpha and beta each land one chop (shared damage), then race the third.
	var hit:=await act(alpha,"axe",TREE)
	expect(hit.ok and hit.message=="砍樹 · 還需要 2 下","alpha chop 1/3 (%s)"%hit.message)
	hit=await act(beta,"axe",TREE)
	expect(hit.ok and hit.message=="砍樹 · 還需要 1 下","beta chop 2/3 continues the shared damage (%s)"%hit.message)
	await settle([alpha,beta])
	for c in [alpha,beta]:
		expect(int(c.damage().get(tile(TREE),-1))==2 and not c.removed().has(tile(TREE)),"%s sees tree damage 2/3 before the race"%c.label)
	var before:=[alpha.bag().duplicate(true),beta.bag().duplicate(true)]
	var pts:=[alpha.points(),beta.points()]
	var coins:=[int(alpha.me().coins),int(beta.me().coins)]
	var outcome:=await race(alpha,beta,"axe",TREE)
	var w:=judge("tree_race",outcome,before,pts,TREE_WIN,GONE,TREE_DROP,true)
	if w<0:return false
	expect(int(alpha.me().coins)==coins[0] and int(beta.me().coins)==coins[1],"tree_race: coins unchanged for both")
	for c in [alpha,beta]:
		expect(c.removed().get(tile(TREE),false)==true and not c.damage().has(tile(TREE)),"%s sees the tree removed and its damage cleared"%c.label)
	await replay([alpha,beta][w],int(outcome[w].sequence),"axe",TREE,"tree_race")
	var retry:=await race(alpha,beta,"axe",TREE)
	expect(retry.size()==2 and not retry[0].ok and not retry[1].ok and retry[0].message==GONE and retry[1].message==GONE,"tree: fresh chops by both after removal are refused (%s)"%str(retry))
	var after_tree:=[ints(alpha.bag()),ints(beta.bag())]

	# 2. Same rock: beta lands one strike, then both race the second.
	hit=await act(beta,"pick",ROCK)
	expect(hit.ok and hit.message=="採集 · 還需要 1 下","beta strike 1/2 on the rock (%s)"%hit.message)
	await settle([alpha,beta])
	for c in [alpha,beta]:
		expect(int(c.damage().get(tile(ROCK),-1))==1 and not c.removed().has(tile(ROCK)),"%s sees rock damage 1/2 before the race"%c.label)
	before=[alpha.bag().duplicate(true),beta.bag().duplicate(true)]
	expect(ints(before[0])==after_tree[0] and ints(before[1])==after_tree[1],"retries and the pre-hit changed no bag")
	pts=[alpha.points(),beta.points()]
	outcome=await race(alpha,beta,"pick",ROCK)
	w=judge("rock_race",outcome,before,pts,ROCK_WIN,GONE,ROCK_DROP,true)
	if w<0:return false
	for c in [alpha,beta]:
		expect(c.removed().get(tile(ROCK),false)==true and not c.damage().has(tile(ROCK)),"%s sees the rock removed and its damage cleared"%c.label)
	await replay([alpha,beta][w],int(outcome[w].sequence),"pick",ROCK,"rock_race")
	retry=await race(alpha,beta,"pick",ROCK)
	expect(retry.size()==2 and not retry[0].ok and not retry[1].ok and retry[0].message==GONE and retry[1].message==GONE,"rock: fresh strikes by both after removal are refused (%s)"%str(retry))

	# 3. Walk to the public quarry by movement input; race the third quarry hit.
	expect(await walk([[alpha,TO_EAST],[beta,TO_EAST]]),"both walk to the public quarry by movement input")
	for c in [alpha,beta]:
		expect(c.pos().distance_to(center(QUARRY))<=3.2,"%s within reach of the quarry (%s)"%[c.label,str(c.pos())])
		expect(int(c.quarry().get("hits",-1))==0 and float(c.quarry().get("ready",-1.0))<=c.time(),"%s sees the quarry fresh and ready"%c.label)
	hit=await act(alpha,"quarry",QUARRY)
	expect(hit.ok and hit.message=="採石 · 再 2 下就能取出石材","alpha quarry hit 1/3 (%s)"%hit.message)
	hit=await act(beta,"quarry",QUARRY)
	expect(hit.ok and hit.message=="採石 · 再 1 下就能取出石材","beta quarry hit 2/3 continues the shared count (%s)"%hit.message)
	await settle([alpha,beta])
	for c in [alpha,beta]:
		expect(int(c.quarry().get("hits",-1))==2,"%s sees quarry hits 2 before the race"%c.label)
	before=[alpha.bag().duplicate(true),beta.bag().duplicate(true)]
	pts=[alpha.points(),beta.points()]
	outcome=await race(alpha,beta,"quarry",QUARRY)
	w=judge("quarry_race",outcome,before,pts,QUARRY_WIN,QUARRY_WAIT,QUARRY_DROP,false)
	if w<0:return false
	var ready_a:=float(alpha.quarry().get("ready",-1.0))
	var ready_b:=float(beta.quarry().get("ready",-2.0))
	expect(int(alpha.quarry().get("hits",-1))==0 and int(beta.quarry().get("hits",-1))==0,"both clients see quarry hits reset to 0")
	expect(absf(ready_a-ready_b)<0.001 and ready_a>alpha.time(),"both clients see the same future quarry ready time (%.2f vs %.2f)"%[ready_a,ready_b])
	await replay([alpha,beta][w],int(outcome[w].sequence),"quarry",QUARRY,"quarry_race")
	expect(absf(float(alpha.quarry().get("ready",-1.0))-ready_a)<0.001 and int(alpha.quarry().get("hits",-1))==0,"quarry replay left the cooldown untouched")

	# 4. Normal shutdown, save on disk, restart, rejoin.
	await settle([alpha,beta])
	var final:={ALPHA:view(alpha),BETA:view(beta)}
	var quarry_ready:=ready_a
	await leave(alpha)
	await leave(beta)
	expect(server.shutdown(),"server Session shuts down with a final save")
	await pause(0.2)
	server_branch.queue_free()
	var disk=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	expect(disk is Dictionary,"save file parses")
	if not disk is Dictionary:return false
	expect(Schema.validate(disk.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"saved world passes SaveSchema")
	expect(disk.removed.get(tile(TREE),false)==true and disk.removed.get(tile(ROCK),false)==true,"save holds the tree and rock as removed")
	expect(not disk.damage.has(tile(TREE)) and not disk.damage.has(tile(ROCK)),"save holds no leftover damage on the tree or rock")
	expect(int(disk.quarry.hits)==0 and absf(float(disk.quarry.ready)-quarry_ready)<0.001,"save holds quarry hits 0 and the raced ready time")
	var ledger=disk.get("ledger",{})
	var journal:Array=ledger.get("entries",[])+ledger.get("rejected",[]) if ledger is Dictionary else []
	expect(journal.is_empty(),"gathering races write no T015 journal rows (not economy actions; got %d)"%journal.size())
	for token in [ALPHA,BETA]:
		var person:Dictionary=disk.players.get(token,{})
		var want:Dictionary=final[token]
		expect(ints(person.get("inventory",{}))==want.inventory and int(person.get("coins",-1))==want.coins and int(person.get("gathering_points",0))==want.points,"save holds %s's inventory/coins/gathering points"%token.left(18))
	var port2:=start_server()
	expect(port2>0,"a new server Session hosts the same save")
	if port2==0:return false
	alpha=await join("alpha",ALPHA,port2)
	beta=await join("beta",BETA,port2)
	expect(joined(alpha) and joined(beta),"both clients rejoin the restarted server")
	if not joined(alpha) or not joined(beta):return false
	expect(same_view(view(alpha),final[ALPHA]),"alpha state identical after restart")
	expect(same_view(view(beta),final[BETA]),"beta state identical after restart")
	for c in [alpha,beta]:
		expect(c.removed().get(tile(TREE),false)==true and c.removed().get(tile(ROCK),false)==true,"%s sees the tree and rock still removed after restart"%c.label)
		expect(absf(float(c.quarry().get("ready",-1.0))-quarry_ready)<0.001 and int(c.quarry().get("hits",-1))==0,"%s sees the same quarry cooldown after restart"%c.label)

	# 5. After restart: the quarry cannot pay instantly, felled targets cannot pay again.
	var bags:=[ints(alpha.bag()),ints(beta.bag())]
	var q:=await act(alpha,"quarry",QUARRY)
	if float(alpha.quarry().get("ready",0.0))>alpha.time() and int(alpha.quarry().get("hits",-1))==0 and not q.ok:
		expect(q.message.begins_with(QUARRY_WAIT),"restart: quarry still cooling down refuses (%s)"%q.message)
	else:
		expect(q.ok and q.message=="採石 · 再 2 下就能取出石材" and int(alpha.quarry().get("hits",-1))==1,"restart: cooled quarry starts a new 3-hit cycle, no instant drop (%s)"%q.message)
	expect(ints(alpha.bag())==bags[0],"restart: quarry hit paid nothing")
	expect(await walk([[alpha,TO_WEST],[beta,TO_WEST]]),"both walk back to the felled tree and rock")
	for target in [[TREE,"axe"],[ROCK,"pick"]]:
		retry=await race(alpha,beta,str(target[1]),target[0])
		expect(retry.size()==2 and retry[0].message==GONE and retry[1].message==GONE and not retry[0].ok and not retry[1].ok,"restart: %s on %s refused for both (%s)"%[target[1],tile(target[0]),str(retry)])
	expect(ints(alpha.bag())==bags[0] and ints(beta.bag())==bags[1],"restart: no second drop for either client")
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
