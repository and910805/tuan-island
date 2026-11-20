extends SceneTree
const Cart=preload("res://scripts/party_cart.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
var state:Dictionary
var active:Dictionary
var checks:=0
var failures:=0

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func fresh(names:Array=["alice","bob"]) -> void:
	state={"time":100.0,"players":{}}
	active={}
	for who in names:
		state.players[who]={"x":Cart.SPAWN.x,"y":Cart.SPAWN.y,"region":Cart.REGION}
		active[who]=true

func at(who:String,cell:Vector2i) -> void:
	state.players[who].x=cell.x+0.5
	state.players[who].y=cell.y+0.5

func act(who:String,cell:Vector2i,extra:String,gallery:bool=true) -> Dictionary:
	return Cart.apply(state,who,cell,extra,gallery,active)

## 站到 cell 後執行。
func do_at(who:String,cell:Vector2i,extra:String) -> Dictionary:
	at(who,cell)
	return act(who,cell,extra)

func snapshot() -> Dictionary:
	return state.duplicate(true)

## 先擺好位置再拍快照，確認被拒絕且 state 完全不變。
func rejects(who:String,from:Vector2i,cell:Vector2i,extra:String,message:String,gallery:bool=true) -> void:
	at(who,from)
	var before:=JSON.stringify(state)
	var result:=act(who,cell,extra,gallery)
	expect(result.ok==false and result.has("message"),"rejected: "+message)
	expect(JSON.stringify(state)==before,"no mutation: "+message)

func rid() -> int:
	return int(state[Cart.KEY].round)

func tick(seconds:float) -> bool:
	state.time=float(state.time)+seconds
	return Cart.step(state,active)

func begin(who:String="alice") -> void:
	expect(do_at(who,Cart.SIGN,"start").ok,"round starts for "+who)

func stop_of() -> int:
	return int(Cart.public_view(state).stop)

func push(who:String="alice") -> Dictionary:
	return do_at(who,Cart.STOPS[stop_of()],"push:%d"%rid())

func ride(who:String="alice") -> void:
	expect(push(who).ok,"push accepted")
	tick(Cart.SEGMENT)

func clear_rock(side:String,who:String="alice") -> void:
	expect(do_at(who,Cart.ROCKS[side],"clear:%d:%s"%[rid(),side]).ok,"clear "+side)

## 從起點到卸貨台：0→1→(2|3)→4→5，共四段。
func run_to_dock(who:String="alice") -> void:
	for i in range(4):
		ride(who)
	expect(stop_of()==Cart.DOCK,"cart reached dock")

func unload(who:String="alice") -> Dictionary:
	return do_at(who,Cart.STOPS[Cart.DOCK],"unload:%d"%rid())

func _initialize() -> void:
	test_constants()
	test_start_and_rejects()
	test_join_cap_and_leave()
	test_push_and_movement()
	test_branches_and_rocks()
	test_deliveries_and_results()
	test_deadline()
	test_disconnect_and_return()
	test_validation()
	test_views()
	test_gallery_world_save()
	print("party_cart checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)

func test_constants() -> void:
	expect(Cart.ACTION=="party_cart" and Cart.VIEW_KEY=="own_party_cart","keys")
	expect(Cart.REGION=="cart_gallery" and Cart.SURFACE=="jinguashi","region and surface")
	expect(Cart.SURFACE_PORTAL==Vector2i(28,25) and Cart.EXIT==Vector2i(11,20) and Cart.SIGN==Vector2i(13,17),"portal, exit, sign")
	expect(Cart.BOUNDS==Rect2i(10,15,22,11) and Cart.SPAWN==Vector2(12.5,20.5),"bounds and spawn")
	expect(Cart.BOUNDS.has_point(Vector2i(Cart.SPAWN)),"spawn inside bounds")
	expect(Cart.JUNCTION==1 and Cart.DOCK==5 and Cart.STOPS.size()==6,"stop ids")
	expect(Cart.STOPS==[Vector2i(15,20),Vector2i(19,20),Vector2i(22,18),Vector2i(22,22),Vector2i(25,20),Vector2i(28,20)],"stop cells")
	expect(Cart.ROCKS=={"north":Vector2i(21,18),"south":Vector2i(21,22)},"rock cells")
	var cells:Array=[]
	cells.append_array(Cart.STOPS)
	cells.append_array(Cart.ROCKS.values())
	cells.append_array([Cart.SIGN,Cart.EXIT])
	for cell in cells:
		expect(Cart.BOUNDS.has_point(cell),"inside bounds %s"%str(cell))
	expect(Cart.DURATION==300.0 and Cart.CRATES==3 and Cart.POINTS==2 and Cart.MAX_PLAYERS==4 and Cart.SEGMENT==1.8 and Cart.REACH==3.2,"tuning")

func test_start_and_rejects() -> void:
	fresh()
	var idle:=Cart.public_view(state)
	expect(idle.phase=="idle" and idle.round==0 and idle.to==-1 and idle.total==3 and idle.players==0,"idle view")
	expect(Cart.valid(state),"no record is valid")
	rejects("alice",Cart.SIGN,Cart.SIGN,"start","start outside gallery",false)
	rejects("alice",Cart.STOPS[0],Cart.STOPS[0],"start","start away from sign")
	rejects("alice",Cart.SIGN+Vector2i(4,0),Cart.SIGN,"start","start too far")
	for bad in ["","begin","start:1","join","join:0","join:01","join:x","push","push:1:2","clear:1","clear:1:east","clear:1:north:x","leave:-1","unload:1.0","switch:1 "]:
		rejects("alice",Cart.SIGN,Cart.SIGN,bad,"unknown payload '%s'"%bad)
	var ghost:=Cart.apply(state,"ghost",Cart.SIGN,"start",true,{"ghost":true})
	expect(not ghost.ok,"unknown player rejected")
	var offline:=Cart.apply(state,"alice",Cart.SIGN,"start",true,{})
	expect(not offline.ok,"offline starter rejected")
	expect(not state.has(Cart.KEY),"nothing written by failures")
	at("alice",Cart.SIGN+Vector2i(3,0))
	expect(act("alice",Cart.SIGN,"start").ok,"within 3.2 reach starts")
	var shared:Dictionary=state[Cart.KEY]
	expect(shared.round==1 and shared.phase=="run" and shared.stop==0 and shared.to==-1,"fresh run record")
	expect(shared.branch=="north" and shared.rocks=={"north":true,"south":true} and shared.delivered==0,"fresh branch and rocks")
	expect(shared.members=={"alice":{"joined":true}},"starter auto-joined")
	rejects("bob",Cart.SIGN,Cart.SIGN,"start","cannot restart a running round")
	rejects("alice",Cart.SIGN,Cart.SIGN,"join:2","stale join")
	rejects("alice",Cart.SIGN,Cart.SIGN,"join:1","double join")
	expect(Cart.valid(state),"started record valid")
	for coin in ["coins","inventory","layers"]:
		expect(not state.players.alice.has(coin) and not state.has(coin),"no normal rewards: "+coin)

func test_join_cap_and_leave() -> void:
	fresh(["a","b","c","d","e"])
	begin("a")
	var r:=rid()
	for who in ["b","c","d"]:
		expect(do_at(who,Cart.SIGN,"join:%d"%r).ok,"join "+who)
	rejects("e",Cart.SIGN,Cart.SIGN,"join:%d"%r,"fifth player")
	expect(act("d",Cart.SIGN,"leave:%d"%r,false).ok,"leave works outside gallery")
	expect(Cart.view(state,"d").joined==false,"left member not joined")
	rejects("e",Cart.SIGN,Cart.SIGN,"join:%d"%r,"leaving does not free an ever-joined slot")
	expect(do_at("d",Cart.SIGN,"join:%d"%r).ok,"former member can rejoin")
	rejects("e",Cart.SIGN,Cart.SIGN,"leave:%d"%r,"non-member leave")
	rejects("a",Cart.SIGN,Cart.SIGN,"leave:%d"%(r+1),"stale leave")
	expect(Cart.public_view(state).players==4,"four joined")
	rejects("e",Cart.STOPS[0],Cart.STOPS[0],"push:%d"%r,"non-member push")

func test_push_and_movement() -> void:
	fresh()
	begin()
	var r:=rid()
	rejects("alice",Cart.STOPS[1],Cart.STOPS[1],"push:%d"%r,"push away from cart tile")
	rejects("alice",Cart.STOPS[0],Cart.STOPS[0],"push:%d"%r,"push outside gallery",false)
	rejects("alice",Cart.STOPS[0]+Vector2i(4,0),Cart.STOPS[0],"push:%d"%r,"push out of reach")
	rejects("alice",Cart.STOPS[0],Cart.STOPS[0],"push:%d"%(r+1),"stale push")
	rejects("alice",Cart.STOPS[0],Cart.STOPS[0],"unload:%d"%r,"unload away from dock")
	rejects("alice",Cart.STOPS[0],Cart.STOPS[0],"switch:%d"%r,"switch away from junction")
	var t0:float=state.time
	expect(do_at("alice",Cart.STOPS[0],"push:%d"%r).ok,"push starts segment")
	var view:=Cart.public_view(state)
	expect(view.stop==0 and view.to==1 and view.departed==t0 and absf(view.arrives-t0-1.8)<0.001,"transit view")
	rejects("alice",Cart.STOPS[0],Cart.STOPS[0],"push:%d"%r,"concurrent push")
	rejects("alice",Cart.STOPS[1],Cart.STOPS[1],"push:%d"%r,"moving cart cannot be pushed from next stop")
	expect(not tick(1.7),"no arrival before 1.8s")
	expect(Cart.public_view(state).to==1,"still moving")
	expect(tick(0.2),"arrival is a persistent change")
	view=Cart.public_view(state)
	expect(view.stop==1 and view.to==-1 and view.departed==0.0 and view.arrives==0.0,"arrived at junction")
	expect(Cart.valid(state),"record valid after arrival")

func test_branches_and_rocks() -> void:
	fresh()
	begin()
	var r:=rid()
	ride()
	expect(stop_of()==1,"at junction")
	rejects("alice",Cart.STOPS[1],Cart.STOPS[1],"push:%d"%r,"north rock blocks north route")
	rejects("alice",Cart.STOPS[0],Cart.STOPS[0],"switch:%d"%r,"switch needs junction tile")
	rejects("alice",Cart.ROCKS.north,Cart.ROCKS.north,"clear:%d:south"%r,"wrong rock tile for branch")
	rejects("alice",Cart.ROCKS.north+Vector2i(4,0),Cart.ROCKS.north,"clear:%d:north"%r,"clear out of reach")
	rejects("alice",Cart.ROCKS.north,Cart.ROCKS.north,"clear:%d:north"%(r+1),"clear stale")
	rejects("alice",Cart.ROCKS.north,Cart.ROCKS.north,"clear:%d:north"%r,"clear outside gallery",false)
	expect(do_at("alice",Cart.STOPS[1],"switch:%d"%r).ok,"switch to south")
	expect(Cart.public_view(state).branch=="south","branch south")
	rejects("alice",Cart.STOPS[1],Cart.STOPS[1],"push:%d"%r,"south rock still blocks")
	clear_rock("south")
	rejects("alice",Cart.ROCKS.south,Cart.ROCKS.south,"clear:%d:south"%r,"already cleared")
	var rocks:Dictionary=Cart.public_view(state).rocks
	expect(rocks.north==true and rocks.south==false,"rocks view: true means obstructed")
	expect(push().ok,"south route works with only south cleared")
	rejects("alice",Cart.STOPS[1],Cart.STOPS[1],"switch:%d"%r,"cannot switch while moving")
	tick(Cart.SEGMENT)
	expect(stop_of()==3,"arrived at south stop")
	rejects("alice",Cart.STOPS[3],Cart.STOPS[3],"switch:%d"%r,"cannot switch away from junction")
	ride()
	expect(stop_of()==4,"merge")
	ride()
	expect(stop_of()==5,"dock")
	rejects("alice",Cart.STOPS[5],Cart.STOPS[5],"push:%d"%r,"cannot push at dock")
	expect(Cart.valid(state),"valid at dock via south")
	expect(unload().ok,"unload")
	var view:=Cart.public_view(state)
	expect(view.stop==0 and view.branch=="south" and view.delivered==1 and view.score==2,"cart restocked; branch latch persists")
	ride()
	expect(push().ok,"second delivery goes south without re-switching")
	expect(Cart.public_view(state).to==3,"latched south")
	tick(Cart.SEGMENT)
	expect(Cart.valid(state),"valid at south stop")
	clear_rock("north")
	expect(Cart.public_view(state).rocks=={"north":false,"south":false},"both cleared")

func test_deliveries_and_results() -> void:
	fresh()
	begin()
	var r:=rid()
	clear_rock("north")
	for n in range(3):
		rejects("alice",Cart.STOPS[5],Cart.STOPS[5],"unload:%d"%r,"cannot unload away from dock")
		run_to_dock()
		rejects("alice",Cart.STOPS[4],Cart.STOPS[4],"unload:%d"%r,"unload on wrong tile")
		rejects("alice",Cart.STOPS[5],Cart.STOPS[5],"unload:%d"%(r+1),"unload stale")
		rejects("alice",Cart.STOPS[5]+Vector2i(4,0),Cart.STOPS[5],"unload:%d"%r,"unload out of reach")
		expect(unload().ok,"unload %d"%(n+1))
		var view:=Cart.public_view(state)
		expect(view.delivered==n+1 and view.score==2*(n+1),"count and score")
		if n<2:
			expect(view.phase=="run" and view.stop==0 and view.to==-1,"cart back at start")
	var done:=Cart.public_view(state)
	expect(done.phase=="results" and done.score==6 and done.delivered==3 and done.remaining==0,"results after third crate")
	expect(done.players==0 and Cart.view(state,"alice").joined==false,"nobody joined in results")
	rejects("alice",Cart.STOPS[0],Cart.STOPS[0],"push:%d"%r,"no push in results")
	rejects("alice",Cart.STOPS[5],Cart.STOPS[5],"unload:%d"%r,"no unload in results")
	expect(not Cart.step(state,active),"results step is idle")
	expect(Cart.valid(state),"results record valid")
	begin("bob")
	var next:=Cart.public_view(state)
	expect(next.round==2 and next.delivered==0 and next.score==0 and next.branch=="north" and next.rocks=={"north":true,"south":true},"new round resets")
	expect(next.players==1 and Cart.view(state,"alice").joined==false and Cart.view(state,"bob").joined,"new roster")
	rejects("alice",Cart.SIGN,Cart.SIGN,"join:%d"%r,"previous round id is stale")

func test_deadline() -> void:
	fresh()
	begin()
	var r:=rid()
	clear_rock("north")
	ride()
	expect(push().ok,"moving at deadline")
	state.time=float(state[Cart.KEY].started)+Cart.DURATION-0.5
	expect(Cart.public_view(state).remaining==1,"remaining rounds up")
	state.time=float(state[Cart.KEY].started)+Cart.DURATION
	rejects("alice",Cart.STOPS[1],Cart.STOPS[1],"push:%d"%r,"expired round rejects actions")
	expect(Cart.step(state,active),"deadline settles")
	var view:=Cart.public_view(state)
	expect(view.phase=="results" and view.to==-1 and view.delivered==0 and view.score==0 and view.remaining==0,"pending movement gives no points")
	expect(Cart.valid(state) and not Cart.step(state,active),"settled and stable")
	fresh()
	begin()
	clear_rock("north")
	run_to_dock()
	state.time=float(state[Cart.KEY].started)+Cart.DURATION+1.0
	expect(Cart.step(state,active),"settle with cart waiting at dock")
	expect(Cart.public_view(state).score==0,"waiting crate scores nothing")
	rejects("alice",Cart.STOPS[5],Cart.STOPS[5],"unload:%d"%rid(),"cannot unload after results")

func test_disconnect_and_return() -> void:
	fresh()
	begin()
	var r:=rid()
	expect(do_at("bob",Cart.SIGN,"join:%d"%r).ok,"bob joins")
	expect(push("alice").ok,"alice pushes")
	active.erase("alice")
	expect(tick(1.0),"disconnect is a persistent change")
	expect(Cart.view(state,"alice").joined==false,"disconnected pusher cleared")
	expect(Cart.public_view(state).to==1,"transit continues after pusher disconnect")
	expect(tick(1.0),"arrival persisted")
	expect(stop_of()==1 and Cart.public_view(state).to==-1,"cart finishes at next stop")
	expect(do_at("bob",Cart.STOPS[1],"switch:%d"%r).ok,"anyone else can take over")
	rejects("alice",Cart.STOPS[1],Cart.STOPS[1],"switch:%d"%r,"disconnected player cannot act")
	active.alice=true
	rejects("alice",Cart.STOPS[1],Cart.STOPS[1],"switch:%d"%r,"must explicitly rejoin")
	expect(do_at("alice",Cart.SIGN,"join:%d"%r).ok,"explicit rejoin")
	clear_rock("south")
	expect(do_at("alice",Cart.STOPS[1],"push:%d"%r).ok,"push on south branch")
	var before:Dictionary=state[Cart.KEY].duplicate(true)
	Cart.return_member(state,"alice")
	var after:Dictionary=state[Cart.KEY]
	expect(Cart.view(state,"alice").joined==false and Cart.view(state,"bob").joined,"return_member clears only that member")
	for field in ["stop","to","departed","arrives","branch","rocks","delivered","score","round","started","phase"]:
		expect(JSON.stringify(after[field])==JSON.stringify(before[field]),"return_member keeps "+field)
	var snap:=JSON.stringify(state)
	Cart.return_member(state,"alice")
	Cart.return_member(state,"nobody")
	expect(JSON.stringify(state)==snap,"return_member is idempotent")
	var empty:Dictionary={"time":0.0,"players":{}}
	Cart.return_member(empty,"alice")
	expect(not empty.has(Cart.KEY),"return_member without record does nothing")

func mutate(label:String,d:Dictionary) -> void:
	match label:
		"unknown field":d.extra=1
		"missing field":d.erase("branch")
		"token not a player":d.members.ghost={"joined":true}
		"too many members":
			for who in ["b","c","d","e"]:
				state.players[who]={}
				d.members[who]={"joined":false}
		"bad member entry":d.members.alice={"joined":1}
		"to not on route":d.to=4
		"arrives inconsistent":d.arrives=float(d.departed)+0.5
		"departed in future":
			d.departed=float(state.time)+50.0
			d.arrives=float(d.departed)+1.8
		"transit with results":d.phase="results"
		"score mismatch":d.score=2
		"branch contradicts rocks":d.rocks.north=true
		"south latch with north stop":d.branch="south"
		"run with all delivered":
			d.delivered=3
			d.score=6
		"idle with times":d.to=-1
		"nan":d.started=NAN
		"round":d.round=0
		"phase":d.phase="idle"
		"started":d.started=999999.0
		"members":d.members={}
		"stop":d.stop=6
		"to":d.to=7
		"branch":d.branch="east"
		"rocks":d.rocks={"north":true}
		"delivered":d.delivered=4

func test_validation() -> void:
	fresh()
	begin()
	clear_rock("north")
	ride()
	expect(push().ok,"in transit")
	var now:float=state.time
	var good:Dictionary=state[Cart.KEY].duplicate(true)
	expect(Cart.valid(state),"transit record valid")
	var labels:=["unknown field","missing field","token not a player","too many members","bad member entry","to not on route",
		"arrives inconsistent","departed in future","transit with results","score mismatch","branch contradicts rocks",
		"south latch with north stop","run with all delivered","idle with times","nan","round","phase","started","members",
		"stop","to","branch","rocks","delivered"]
	for label in labels:
		fresh()
		state.time=now
		var record:Dictionary=good.duplicate(true)
		mutate(label,record)
		state[Cart.KEY]=record
		expect(not Cart.valid(state),"invalid: "+label)
	fresh()
	state.time=now
	state[Cart.KEY]=good.duplicate(true)
	expect(Cart.valid(state),"unmutated copy is valid")
	fresh()
	state[Cart.KEY]={"round":1}
	var before:=JSON.stringify(state)
	at("alice",Cart.SIGN)
	before=JSON.stringify(state)
	expect(not act("alice",Cart.SIGN,"start").ok,"corrupt record rejects start")
	expect(not act("alice",Cart.SIGN,"leave:1",false).ok,"corrupt record rejects leave")
	expect(JSON.stringify(state)==before,"corrupt record untouched")
	expect(Cart.public_view(state).phase=="idle" and Cart.view(state,"alice").joined==false,"corrupt record reads as idle")
	expect(not Cart.step(state,active),"corrupt record step is a no-op")
	expect(not Cart.valid({"time":0.0}),"players required")
	fresh()
	begin()
	var parsed:Variant=JSON.parse_string(JSON.stringify(state))
	expect(parsed is Dictionary and Cart.valid(parsed),"JSON round trip valid")
	expect(parsed[Cart.KEY].round is int and parsed[Cart.KEY].stop is int and parsed[Cart.KEY].to is int,"integers normalised")

func test_views() -> void:
	fresh()
	begin()
	expect(do_at("bob",Cart.SIGN,"join:%d"%rid()).ok,"bob joins")
	var view:=Cart.public_view(state)
	var keys:Array=view.keys()
	keys.sort()
	expect(keys==["arrives","branch","delivered","departed","phase","players","remaining","rocks","round","score","stop","to","total"],"shared view fields")
	expect(view.phase=="run" and view.round==1 and view.remaining==300 and view.players==2 and view.total==3,"shared view values")
	expect(view.to==-1 and view.stop==0 and view.departed is float and view.arrives is float,"shared view types")
	var text:=JSON.stringify(view)
	expect(not text.contains("alice") and not text.contains("bob"),"public view has no tokens")
	expect(Cart.view(state,"alice")=={"joined":true} and Cart.view(state,"zed")=={"joined":false},"own view")
	tick(30.2)
	expect(Cart.public_view(state).remaining==270,"remaining counts down in world seconds")

func test_gallery_world_save() -> void:
	var world:=World.new()
	var actor:="gallery-migration-qa"
	world.add_player(actor,"試車旅人")
	world.state.regions.erase(Cart.REGION)
	var loaded:Dictionary=JSON.parse_string(JSON.stringify(world.state))
	expect(Schema.validate(loaded,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Old world without the gallery loads")
	expect(loaded.regions[Cart.REGION]==World.REGIONS.fresh(),"New gallery starts with empty and independent layers")
	expect(loaded.players[actor].inventory==world.state.players[actor].inventory,"Migration preserves the player's bag")

	var bad:=loaded.duplicate(true)
	bad.regions[Cart.REGION].ground[World.key(Cart.STOPS[0])]={"type":"floor","owner":actor}
	expect(not Schema.validate(bad,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Gallery cannot load saved construction")
	world.state=loaded
	var person:Dictionary=world.state.players[actor]
	person.region=Cart.REGION
	person.x=Cart.SIGN.x+0.5
	person.y=Cart.SIGN.y+0.5
	expect(world.act(actor,"gallery-start",Cart.ACTION,Cart.SIGN,"start").ok,"World starts the round in the gallery")
	person.x=Cart.STOPS[0].x+0.5
	person.y=Cart.STOPS[0].y+0.5
	expect(world.act(actor,"gallery-push",Cart.ACTION,Cart.STOPS[0],"push:1").ok,"World commits a moving cart")
	var path:="user://party-cart-restart-%d.json"%OS.get_process_id()
	world.save_path=path
	expect(world.save(),"Moving cart save is durable")
	var resumed:=World.new()
	expect(resumed.load_world(path),"A new server reloads the moving cart")
	var moving:=Cart.public_view(resumed.state)
	expect(moving.get("to")==Cart.JUNCTION and moving.get("players")==0,"Restart keeps the scheduled stop and releases disconnected members")
	expect(resumed.step(Cart.SEGMENT+0.01,true,false),"Resumed world finishes the segment")
	var stopped:=Cart.public_view(resumed.state)
	expect(stopped.get("stop")==Cart.JUNCTION and stopped.get("to")==-1 and stopped.get("score")==0,"Closing the segment brakes the cart with no phantom score")
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
