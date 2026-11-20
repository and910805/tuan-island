extends SceneTree
## Q05 河對岸的鈴聲 focused regression (pure World, no scene; works with --headless).
## Not run by the author (no shell in the authoring session): Codex runs it.
##
## Contract pinned here:
##   - Q05 = 60 wood + 4 rope (board action `bridge_donate`, capped) + 2 workbench foundations (10 stone each,
##     so 20 stone in total and never another 20 on top). Rope comes from 5 fiber each (`handcraft_rope`).
##   - Q03 (`donate` 30 wood + 10 stone, public fund) is untouched and stays a separate server state.
##   - Any contribution order works; different players can complete the project; `done` flips exactly once.
##   - Duplicate request ids, overfull bags, wrong cell / distance / extra, no Q03, finished or legacy worlds
##     change nothing.
##   - Legacy saves: absent project = open bridge; C11 {foundations,done} saves keep their count (done = open,
##     pending = owes wood 60 and rope 4); the first Q05 write upgrades the shape lazily.
##   - Real passage over the bridge tiles and the 河灣橋釣點 catch after opening; other fishing paths unchanged.

const World=preload("res://scripts/world.gd")
const I=World.INDUSTRY
const S=World.STONE_WORKSHOP
const Collections=preload("res://scripts/collections.gd")
const KIND:="stone_workbench"
const BOARD:=Vector2i(40,29)
const HOME:=Vector2i(40,35)
const BRIDGE_TILES:=[Vector2i(55,29),Vector2i(55,30),Vector2i(55,31),Vector2i(56,29),Vector2i(56,30),Vector2i(56,31)]
const POOL_TILE:=Vector2i(55,28)
const SOUTH_POOL_TILE:=Vector2i(56,32)
const MEET_TILE:=Vector2i(55,35)

var world:World
var owner:="q05-owner"
var guest:="q05-guest"
var third:="q05-third"
var path:String
var checks:=0
var failures:=0
var serial:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func act(verb:String,tile:Vector2i,extra:="",who:="")->Dictionary:
	serial+=1
	return world.act(owner if who.is_empty() else who,"q05-%d"%serial,verb,tile,extra)

func valid(state:Dictionary)->bool:
	return bool(World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME))

func centre(tile:Vector2i)->Vector2:
	return Vector2(tile)+Vector2(0.5,0.5)

func put(token:String,at:Vector2)->void:
	world.state.players[token].x=at.x
	world.state.players[token].y=at.y

func bag(item:String,who:="")->int:
	return int(world.state.players[owner if who.is_empty() else who].inventory.get(item,0))

func give_bag(who:String,items:Dictionary)->void:
	world.state.players[who].inventory=items.duplicate()

func project()->Dictionary:
	return world.state.get(S.PROJECT_KEY,{})

func walkable(tile:Vector2i)->bool:
	return not world.water(tile) and world.can_stand(centre(tile))

func bridge_walkable()->bool:
	for tile:Vector2i in BRIDGE_TILES:
		if not walkable(tile):return false
	return true

func bridge_closed()->bool:
	for tile:Vector2i in BRIDGE_TILES:
		if not world.water(tile) or world.can_stand(centre(tile)):return false
	return true

## A brand new island: yard cleared, Q03 and Q05 progress gone, three joined players with empty bags.
func fresh()->void:
	for x in range(38,51):
		for y in range(33,41):
			var k:=World.key(Vector2i(x,y))
			world.state.objects.erase(k)
			world.state.crops.erase(k)
			world.state.ground.erase(k)
	world.state.board=false
	world.state.donations={"wood":0,"stone":0}
	world.state.erase(S.PROJECT_KEY)
	world.state.erase("public_fund")
	world.state.events=[]
	world.state.time=720.0
	for who:String in [owner,guest,third]:
		var person:Dictionary=world.state.players[who]
		person.inventory={}
		person.crafting_points=0
		person.erase("resident_participation")
		person.erase("fishing")
		person.receipts={}
	put(owner,Vector2(41.0,36.7))
	put(guest,Vector2(49.5,39.5))
	put(third,Vector2(48.5,39.5))

func at_board(who:String)->void:
	put(who,centre(BOARD)+Vector2(0.0,1.0))

func at_station(who:String)->void:
	put(who,Vector2(41.0,36.7))

## Real Q03: donate 30 wood + 10 stone at the board.
func q03()->void:
	give_bag(owner,{"wood":30,"stone":10})
	at_board(owner)
	var done:=act("donate",BOARD)
	expect(done.ok and world.state.board==true and world.state.donations=={"wood":30,"stone":10},"Q03 completes through the real donate action: "+str(done.get("message","")))
	expect(project()=={"foundations":0,"done":false},"Q05 starts as a pending C11-shaped project (nothing donated)")

## Q03 + the station; the owner keeps `stone` stone and `wood` wood afterwards.
func ready_island(stone:int,wood:int)->void:
	fresh()
	q03()
	give_bag(owner,{"wood":8+wood,"stone":20+stone})
	at_station(owner)
	var built:=act("build",HOME,KIND)
	expect(built.ok and bag("stone")==stone and bag("wood")==wood,"the workbench costs exactly 20 stone + 8 wood: "+str(built.get("message","")))

func craft(who:="")->Dictionary:
	var token:=owner if who.is_empty() else who
	at_station(token)
	return act(S.ACTION,HOME,S.FOUNDATION,token)

func donate(who:="",extra:="")->Dictionary:
	var token:=owner if who.is_empty() else who
	at_board(token)
	return act(S.DONATE_ACTION,BOARD,extra,token)

func state_without_receipts()->Dictionary:
	var copy:=world.state.duplicate(true)
	for who:String in copy.players:copy.players[who].erase("receipts")
	copy.erase("events")
	return copy

func finish()->void:
	for suffix in ["",".bak",".tmp",".staged",".writer-lock",".corrupt"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("BRIDGE_Q05_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

# -------------------------------------------------------------- scenarios --

func contract_scenario()->void:
	expect(S.WOOD_NEEDED==60 and S.ROPE_NEEDED==4 and S.FOUNDATIONS_NEEDED==2 and S.FOUNDATION_COST=={"stone":10},"Q05 prices: 60 wood, 4 rope, 2 foundations of 10 stone")
	expect(S.FOUNDATIONS_NEEDED*int(S.FOUNDATION_COST.stone)==20,"the foundations ARE the 20 stone")
	expect(S.DONATE_ACTION=="bridge_donate" and S.DONATE_ACTION!="donate","Q05 has its own action, distinct from the Q03 donate")
	expect(World.ROPE_FIBER_COST==5,"rope is 5 fiber by hand (the natural source)")
	expect(S.bridge_open({"board":true}) and not S.bridge_open({"board":true,S.PROJECT_KEY:S.fresh_project()}) and not S.bridge_open({"board":false}),"bridge_open keeps the C11 meaning")
	expect(S.missing({"board":true,S.PROJECT_KEY:{"foundations":1,"done":false}})=={"foundations":1,"wood":60,"rope":4},"a C11-shaped pending project owes wood 60 and rope 4 (migration default)")
	expect(S.missing({"board":true})=={"foundations":0,"wood":0,"rope":0},"no project owes nothing")
	expect(S.contribution({"board":true,S.PROJECT_KEY:S.fresh_project()},{"wood":100,"rope":9})=={"wood":60,"rope":4},"a contribution preview never exceeds what is missing")
	expect(S.contribution({"board":true,S.PROJECT_KEY:S.fresh_project()},{"wood":7})=={"wood":7,"rope":0},"a contribution preview never exceeds what is carried")
	expect(Collections.FISH.has("redfish") and Collections.FISH.has("loach"),"the bridge pool catches are real fish")

func journey_foundations_first_scenario()->void:
	# Q03 -> workbench -> rope from fiber -> foundations first, then the board takes wood and rope.
	ready_island(40,100)
	give_bag(owner,{"stone":40,"wood":100,"fiber":20})
	var points:=int(world.state.players[owner].crafting_points)
	for index in 4:
		expect(act("handcraft_rope",Vector2i.ZERO).ok,"fiber -> rope %d"%(index+1))
	expect(bag("rope")==4 and bag("fiber")==0,"4 rope woven from exactly 20 fiber")
	var first_foundation:=craft()
	expect(first_foundation.ok and int(project().foundations)==1 and bag("stone")==30,"first foundation costs 10 stone")
	expect(bridge_closed(),"one foundation does not open the river")
	expect(craft().ok and int(project().foundations)==2 and bag("stone")==20 and project().done==false and bridge_closed(),"second foundation: 20 stone spent in total, still closed (wood and rope owed)")
	expect(project().size()==4 and project().wood==0 and project().rope==0,"the project upgraded to the four-field shape keeping the foundations")
	expect(not craft().ok and bag("stone")==20 and int(project().foundations)==2,"no third foundation, nothing charged")
	var gave:=donate()
	expect(gave.ok and project().wood==60 and project().rope==4 and project().done==true,"the board takes exactly 60 wood + 4 rope and opens the bridge: "+str(gave.get("message","")))
	expect(bag("wood")==40 and bag("rope")==0 and bag("stone")==20,"wood 100 -> 40, rope 4 -> 0 and no extra stone was charged")
	expect(bridge_walkable(),"the bridge is walkable")
	expect(world.state.events.filter(func(line):return str(line).contains("河灣橋開通")).size()==1,"completion is announced exactly once")
	expect(valid(world.state.duplicate(true)),"the finished world validates")
	expect(world.state.players[owner].resident_participation.get("bridge")==true,"bridge participation is recorded")
	expect(int(world.state.players[owner].crafting_points)==points+4+2+0,"crafting points: 4 ropes + 2 foundations")

func journey_materials_first_scenario()->void:
	# The other order: wood and rope first (even before the station exists), foundations last.
	fresh()
	q03()
	give_bag(owner,{"wood":60,"rope":4})
	var early:=donate()
	expect(early.ok and project().wood==60 and project().rope==4 and int(project().foundations)==0 and project().done==false and bridge_closed(),"wood and rope can be donated before the workbench exists")
	give_bag(owner,{"wood":8,"stone":40})
	at_station(owner)
	expect(act("build",HOME,KIND).ok,"build the station afterwards")
	expect(craft().ok and project().done==false and bridge_closed(),"one foundation after the materials: still closed")
	var stone:=bag("stone")
	var last:=craft()
	expect(last.ok and project().done==true and bridge_walkable() and bag("stone")==stone-10,"the last foundation completes and opens the bridge: "+str(last.get("message","")))
	expect(str(last.message).contains("河灣橋開通"),"the completion message says the bridge opened")
	expect(world.state.events.filter(func(line):return str(line).contains("河灣橋開通")).size()==1,"announced exactly once")

func two_players_scenario()->void:
	ready_island(0,0)
	give_bag(owner,{"stone":10,"wood":40})
	give_bag(guest,{"stone":10,"wood":40,"rope":2})
	give_bag(third,{"wood":5,"rope":9})
	expect(craft().ok,"owner makes foundation 1")
	expect(donate().ok and project().wood==40 and project().rope==0,"owner gives 40 wood (no rope)")
	var second:=donate(guest)
	expect(second.ok and project().wood==60 and project().rope==2 and bag("wood",guest)==20 and bag("rope",guest)==0,"a friend tops the wood up to exactly 60 and adds rope")
	expect(craft(guest).ok and int(project().foundations)==2 and project().done==false,"the friend makes foundation 2: still owes rope")
	var done:=donate(third)
	expect(done.ok and project().rope==4 and bag("rope",third)==7 and bag("wood",third)==5 and project().done==true and bridge_walkable(),"a third player's 2 rope complete the bridge, taking exactly what was missing")
	expect(world.state.players[owner].resident_participation.get("bridge")==true and world.state.players[guest].resident_participation.get("bridge")==true and world.state.players[third].resident_participation.get("bridge")==true,"everyone who helped has bridge participation")

func guard_scenario()->void:
	# Before Q03 nothing can be donated or crafted and nothing changes.
	fresh()
	give_bag(owner,{"wood":60,"rope":4,"stone":30})
	at_board(owner)  # canonical pose first: donate() only re-applies it, so the snapshot stays comparable
	var before:=state_without_receipts()
	var early:=donate()
	expect(not early.ok and str(early.message)==S.DONATE_WAIT_MSG and state_without_receipts()==before,"bridge_donate before Q03 is refused atomically: "+str(early.get("message","")))
	var early_fund:=act("fund_bridge",BOARD)
	expect(not early_fund.ok,"the public fund cannot pay Q05")
	# Q03 done; now every unauthorized variant.
	fresh()
	q03()
	give_bag(owner,{"wood":60,"rope":4})
	before=state_without_receipts()
	at_board(owner)
	expect(not act(S.DONATE_ACTION,Vector2i(41,29)).ok and state_without_receipts()==before,"the wrong cell is refused")
	put(owner,centre(BOARD)+Vector2(7.0,0.0))
	var far_before:=state_without_receipts()  # snapshot in the far pose; only the refusal may differ from it
	expect(not act(S.DONATE_ACTION,BOARD).ok and state_without_receipts()==far_before,"standing far from the board is refused")
	at_board(owner)
	expect(not act(S.DONATE_ACTION,BOARD,"wood").ok and not act(S.DONATE_ACTION,BOARD,"999").ok and state_without_receipts()==before,"a payload (client-chosen amount or item) is refused")
	expect(not world.act("nobody","q05-ghost",S.DONATE_ACTION,BOARD,"").ok,"an unknown player is refused")
	give_bag(owner,{"stone":50,"fiber":4})
	before=state_without_receipts()
	var empty:=donate()
	expect(not empty.ok and str(empty.message)==S.DONATE_NONE_MSG and state_without_receipts()==before,"nothing relevant in the bag: refused, no change, the message names the rope source")
	# The Q03 donate stays a different thing: it never feeds Q05 and refuses (and points at Q05) once the board is fixed.
	give_bag(owner,{"wood":60,"rope":4})
	var q03_again:=act("donate",BOARD)
	expect(not q03_again.ok and str(q03_again.message).contains("Q05") and int(project().get("wood",0))==0 and bag("wood")==60,"the Q03 donate does not take Q05 materials")
	# Craft guards.
	expect(not act(S.ACTION,HOME,S.FOUNDATION).ok,"no station: no foundation")
	# Done / legacy worlds refuse and keep the bag.
	ready_island(0,0)
	give_bag(owner,{"wood":60,"rope":4,"stone":20})
	expect(craft().ok and craft().ok and donate().ok and project().done==true,"fixture: a finished project")
	give_bag(owner,{"wood":9,"rope":9})
	before=state_without_receipts()
	var again:=donate()
	expect(not again.ok and str(again.message)==S.BRIDGE_DONE_MSG and state_without_receipts()==before and bridge_walkable(),"a finished project takes nothing more")

func duplicate_and_overfill_scenario()->void:
	ready_island(0,0)
	give_bag(owner,{"wood":100,"rope":9})
	at_board(owner)
	var first:=world.act(owner,"q05-dup","bridge_donate",BOARD,"")
	expect(first.ok and project().wood==60 and project().rope==4 and bag("wood")==40 and bag("rope")==5,"an overfull bag gives exactly 60 wood and 4 rope")
	var after_first:=state_without_receipts()
	var replay:=world.act(owner,"q05-dup","bridge_donate",BOARD,"")
	expect(replay==first and state_without_receipts()==after_first,"a retried request id is answered from its receipt and changes nothing")
	var another:=world.act(owner,"q05-dup-2","bridge_donate",BOARD,"")
	expect(not another.ok and state_without_receipts()["players"][owner]["inventory"]==after_first["players"][owner]["inventory"],"a fresh request with nothing missing is refused and keeps the bag")
	# Partial then cap: the caps are per item.
	ready_island(0,0)
	give_bag(owner,{"wood":59,"rope":1})
	expect(donate().ok and project().wood==59 and project().rope==1,"a partial donation records exactly what was carried")
	give_bag(owner,{"wood":5,"rope":5})
	var topped:=donate()
	expect(topped.ok and project().wood==60 and project().rope==4 and bag("wood")==4 and bag("rope")==2,"the next donation only takes the missing 1 wood and 3 rope")
	# Duplicate foundation craft.
	ready_island(0,0)
	give_bag(owner,{"stone":10})
	at_station(owner)
	var c1:=world.act(owner,"q05-craft","stone_craft",HOME,S.FOUNDATION)
	var c2:=world.act(owner,"q05-craft","stone_craft",HOME,S.FOUNDATION)
	expect(c1.ok and c2==c1 and int(project().foundations)==1 and bag("stone")==0,"a retried foundation craft is not charged twice")
	give_bag(owner,{"stone":9})
	expect(not craft().ok and int(project().foundations)==1 and bag("stone")==9,"9 stone is refused and kept")

func fund_and_q03_scenario()->void:
	# Shared fund still finishes Q03 and leaves Q05 pending; prior partial Q03 donations survive.
	fresh()
	world.state.donations={"wood":12,"stone":3}
	world.state.public_fund={"balance":100000,"contributors":{}}
	at_board(owner)
	var funded:=act("fund_bridge",BOARD)
	expect(funded.ok and world.state.board==true and world.state.donations=={"wood":30,"stone":10},"the fund still completes Q03")
	expect(project()=={"foundations":0,"done":false} and bridge_closed(),"and leaves Q05 pending with the river closed")
	expect(str(funded.message).contains("河灣橋") and str(funded.message).contains("繩索"),"its message names the Q05 requirements")
	var again:=act("fund_bridge",BOARD)
	expect(not again.ok,"the fund cannot settle twice")
	give_bag(owner,{"wood":60,"rope":4})
	expect(donate().ok and project().wood==60,"Q05 can still be donated after a fund-paid Q03")

func reload_scenario()->void:
	ready_island(10,0)
	give_bag(owner,{"stone":10,"wood":25,"rope":3})
	expect(craft().ok and donate().ok and int(project().foundations)==1 and project().wood==25 and project().rope==3,"fixture: part of Q05 done")
	expect(world.save(),"the half-done world saves")
	var warm:=World.new()
	expect(warm.load_world(path) and not warm.recovered_from_backup,"warm reload from the primary save")
	expect(warm.state.get(S.PROJECT_KEY)=={"foundations":1,"done":false,"wood":25,"rope":3},"every Q05 counter survives the reload")
	expect(int(warm.state.donations.get("wood",-1))==30 and int(warm.state.donations.get("stone",-1))==10 and warm.state.donations.size()==2 and warm.state.board==true,"Q03 totals survive the reload (exact integer amounts)")
	expect(warm.water(BRIDGE_TILES[0]),"the bridge is still closed after the reload")
	warm.save_path=path
	warm.state.players[owner].inventory={"wood":99,"rope":9,"stone":10}
	warm.state.players[owner].x=centre(BOARD).x
	warm.state.players[owner].y=centre(BOARD).y+1.0
	expect(warm.act(owner,"q05-warm-1","bridge_donate",BOARD,"").ok and warm.state.bridge_project.wood==60 and warm.state.bridge_project.rope==4 and warm.state.bridge_project.done==false,"the reloaded world takes the missing wood and rope")
	warm.state.players[owner].x=41.0
	warm.state.players[owner].y=36.7
	var last:=warm.act(owner,"q05-warm-2","stone_craft",HOME,S.FOUNDATION)
	expect(last.ok and warm.state.bridge_project.done==true and not warm.water(BRIDGE_TILES[0]),"the reloaded world finishes Q05: "+str(last.get("message","")))
	expect(warm.save(),"the finished world saves")
	var done:=World.new()
	expect(done.load_world(path) and done.state.bridge_project=={"foundations":2,"done":true,"wood":60,"rope":4} and not done.water(BRIDGE_TILES[2]),"the open bridge survives a second reload")

func legacy_scenario()->void:
	# 1) Pre-C11: board done, no project -> open bridge for good, nothing to donate or craft.
	fresh()
	world.state.board=true
	world.state.donations={"wood":30,"stone":10}
	expect(bridge_walkable() and valid(world.state.duplicate(true)),"a pre-C11 completed world keeps its open bridge")
	give_bag(owner,{"wood":60,"rope":4})
	at_board(owner)
	var before:=state_without_receipts()
	expect(not donate().ok and state_without_receipts()==before,"a legacy world has nothing to donate")
	expect(world.save(),"the legacy world saves")
	var legacy:=World.new()
	expect(legacy.load_world(path) and not legacy.state.has(S.PROJECT_KEY) and not legacy.water(BRIDGE_TILES[1]),"actual reload: still open, no project appears")
	# 2) C11 in progress (two-field shape, one foundation): count kept, wood/rope owed as 0 donated, validates as-is.
	fresh()
	world.state.board=true
	world.state.donations={"wood":30,"stone":10}
	world.state[S.PROJECT_KEY]={"foundations":1,"done":false}
	expect(valid(world.state.duplicate(true)) and bridge_closed(),"a C11 in-progress save validates and the bridge stays closed")
	expect(world.save(),"the C11 in-progress world saves")
	var pending:=World.new()
	expect(pending.load_world(path) and pending.state.get(S.PROJECT_KEY)=={"foundations":1,"done":false},"actual reload keeps the C11 shape untouched (no migration on load)")
	pending.save_path=path
	pending.state.players[owner].inventory={"wood":70,"rope":6}
	pending.state.players[owner].x=centre(BOARD).x
	pending.state.players[owner].y=centre(BOARD).y+1.0
	var upgraded:=pending.act(owner,"q05-c11-1","bridge_donate",BOARD,"")
	expect(upgraded.ok and pending.state.bridge_project=={"foundations":1,"done":false,"wood":60,"rope":4},"the first Q05 donation upgrades the shape and keeps the foundation: "+str(upgraded.get("message","")))
	expect(bool(World.SAVE_SCHEMA.validate(pending.state.duplicate(true),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)),"the upgraded world validates")
	# 3) C11 finished (two-field, done) stays open and owes nothing.
	fresh()
	world.state.board=true
	world.state.donations={"wood":30,"stone":10}
	world.state[S.PROJECT_KEY]={"foundations":2,"done":true}
	give_bag(owner,{"wood":60,"rope":4})
	at_board(owner)
	before=state_without_receipts()
	expect(bridge_walkable() and valid(world.state.duplicate(true)) and not donate().ok and state_without_receipts()==before,"a C11 finished project stays open, valid and takes nothing")
	# 4) C11 pending with the foundations already complete cannot exist in the old shape: still rejected.
	var impossible:=world.state.duplicate(true)
	impossible[S.PROJECT_KEY]={"foundations":2,"done":false}
	expect(not valid(impossible),"two-field 2/2 not-done is still rejected (it would be a stuck world)")
	# 5) A C11 world that crafts the second foundation before donating: upgrades, stays closed.
	fresh()
	world.state.board=true
	world.state.donations={"wood":30,"stone":10}
	world.state[S.PROJECT_KEY]={"foundations":1,"done":false}
	world.state.objects[World.key(HOME)]={"type":KIND,"owner":owner,"items":{},"stone_bench_part":0}
	world.state.objects[World.key(HOME+Vector2i.RIGHT)]={"type":KIND,"owner":owner,"items":{},"stone_bench_part":1}
	give_bag(owner,{"stone":10})
	var late:=craft()
	expect(late.ok and project()=={"foundations":2,"done":false,"wood":0,"rope":0} and bridge_closed(),"a C11 world finishing its foundations first still owes wood and rope: "+str(late.get("message","")))
	expect(str(late.message).contains("木材") and str(late.message).contains("繩索"),"the message says what is still missing")

func validator_scenario()->void:
	ready_island(0,0)
	give_bag(owner,{"wood":10,"rope":1})
	expect(donate().ok,"fixture: a four-field project")
	var good:=world.state.duplicate(true)
	expect(valid(good),"the four-field fixture validates")
	var cases:={}
	var many_wood:=good.duplicate(true);many_wood[S.PROJECT_KEY]={"foundations":0,"done":false,"wood":61,"rope":1};cases["too much wood"]=many_wood
	var many_rope:=good.duplicate(true);many_rope[S.PROJECT_KEY]={"foundations":0,"done":false,"wood":10,"rope":5};cases["too much rope"]=many_rope
	var text_wood:=good.duplicate(true);text_wood[S.PROJECT_KEY]={"foundations":0,"done":false,"wood":"10","rope":1};cases["wood as text"]=text_wood
	var neg:=good.duplicate(true);neg[S.PROJECT_KEY]={"foundations":0,"done":false,"wood":-1,"rope":1};cases["negative wood"]=neg
	var frac:=good.duplicate(true);frac[S.PROJECT_KEY]={"foundations":0,"done":false,"wood":10.5,"rope":1};cases["fractional wood"]=frac
	var early:=good.duplicate(true);early[S.PROJECT_KEY]={"foundations":2,"done":true,"wood":59,"rope":4};cases["done before the wood"]=early
	var no_rope:=good.duplicate(true);no_rope[S.PROJECT_KEY]={"foundations":2,"done":true,"wood":60,"rope":3};cases["done before the rope"]=no_rope
	var stuck:=good.duplicate(true);stuck[S.PROJECT_KEY]={"foundations":2,"done":false,"wood":60,"rope":4};cases["everything in but not done"]=stuck
	var odd:=good.duplicate(true);odd[S.PROJECT_KEY]={"foundations":0,"done":false,"wood":10};cases["three fields"]=odd
	var extra:=good.duplicate(true);extra[S.PROJECT_KEY]={"foundations":0,"done":false,"wood":10,"rope":1,"note":1};cases["five fields"]=extra
	var no_board:=good.duplicate(true);no_board.board=false;cases["a project without the board"]=no_board
	for label:String in cases:expect(not valid(cases[label]),"the validator rejects: "+label)
	var complete:=good.duplicate(true);complete[S.PROJECT_KEY]={"foundations":2,"done":true,"wood":60,"rope":4}
	expect(valid(complete),"a complete four-field project validates")

func passage_and_fishing_scenario()->void:
	# Closed river: not walkable, and its banks are ordinary fishing.
	ready_island(0,0)
	expect(bridge_closed(),"before Q05 every bridge tile is water and blocked")
	expect(not S.fishing_spot(world.state,POOL_TILE),"before the bridge opens the pool is not a special spot")
	put(owner,Vector2(54.5,28.5))
	var ordinary:=act("fish_start",POOL_TILE)
	expect(ordinary.ok,"the pre-existing river fishing still works while the bridge is closed: "+str(ordinary.get("message","")))
	world.state.players[owner].erase("fishing")
	# Open the project through the real actions.
	give_bag(owner,{"stone":20,"wood":60,"rope":4})
	expect(craft().ok and craft().ok and donate().ok and bridge_walkable(),"Q05 completes with real actions and the deck tiles are walkable")
	# Actually walking: every deck tile is standable and the east bank is reachable tile by tile.
	expect(World.land(Vector2i(54,30)) and World.land(Vector2i(57,30)) and not world.water(Vector2i(54,30)) and not world.water(Vector2i(57,30)),"both banks are dry land")
	var deck:=true
	for x in [55,56]:
		for y in [29,30,31]:
			if world.water(Vector2i(x,y)) or not world.can_stand(centre(Vector2i(x,y))):deck=false
	expect(deck,"all six deck tiles are standable, so the two banks are joined")
	expect(world.water(Vector2i(55,28)) and world.water(Vector2i(56,32)) and world.water(Vector2i(55,33)),"the river beside the deck is still water")
	# The spot.
	expect(S.fishing_spot(world.state,POOL_TILE) and S.fishing_spot(world.state,SOUTH_POOL_TILE),"the water north and south of the deck is the 河灣橋釣點")
	expect(not S.fishing_spot(world.state,Vector2i(55,30)) and not S.fishing_spot(world.state,MEET_TILE) and not S.fishing_spot(world.state,Vector2i(55,20)),"the deck, the fishing-meet waters and the far river are not the spot")
	expect(Collections.fishing_result("home","spring",0,{},720.0,S.FISHING_SPOT).id=="redfish" and Collections.fishing_result("home","spring",7,{},1300.0,S.FISHING_SPOT).id=="loach","the pool pays redfish by day and loach by night, whatever the catch count")
	expect(Collections.fishing_result("home","spring",0,{},720.0,"coast").id in Collections.FRESHWATER_FISH,"the ordinary river catch is unchanged")
	expect(Collections.fishing_result("home","spring",0,{},720.0,World.WANGAN_COAST.FISHING_SPOT).id=="sardine","the Wangan south shore is unchanged")
	# A real cast from the deck.
	put(owner,centre(Vector2i(55,29)))
	var redfish:=bag("redfish")
	var cast:=act("fish_start",POOL_TILE)
	expect(cast.ok and world.state.players[owner].has("fishing"),"casting at the pool from the bridge works: "+str(cast.get("message","")))
	world.state.time+=4.0
	var reel:=act("fish_catch",POOL_TILE)
	expect(reel.ok and bag("redfish")==redfish+1 and not world.state.players[owner].has("fishing"),"reeling in lands the pool's own catch in the bag: "+str(reel.get("message","")))
	expect(int(world.state.players[owner].get("fish_caught",0))>=1,"the catch counts toward the angling record")
	# Night cast from the south side.
	world.state.time=1300.0
	put(owner,centre(Vector2i(56,31)))
	var loach:=bag("loach")
	expect(act("fish_start",SOUTH_POOL_TILE).ok,"casting at the south pool at night works")
	world.state.time+=4.0
	var night:=act("fish_catch",SOUTH_POOL_TILE)
	expect(night.ok and bag("loach")==loach+1,"the south pool pays loach at night: "+str(night.get("message","")))
	# The fishing meet waters keep their own rules (and an ordinary river catch).
	world.state.time=720.0
	put(owner,Vector2(54.5,35.5))
	expect(act("fish_start",MEET_TILE).ok,"the river south of the spot is still fishable")
	world.state.players[owner].erase("fishing")
	# Passage and spot survive a reload.
	expect(world.save(),"the open world saves")
	var reloaded:=World.new()
	expect(reloaded.load_world(path) and S.fishing_spot(reloaded.state,POOL_TILE) and not reloaded.water(BRIDGE_TILES[3]),"the bridge and the pool survive a reload")
	# Legacy open bridge gets the spot too (it is a property of the open bridge).
	fresh()
	world.state.board=true
	expect(S.fishing_spot(world.state,POOL_TILE),"a grandfathered open bridge also has the 河灣橋釣點")

func run()->void:
	path="user://bridge-q05-%d.json"%Time.get_ticks_usec()
	world=World.new()
	world.save_path=path
	world.add_player(owner,"橋工")
	world.add_player(guest,"旅客")
	world.add_player(third,"鄰居")
	world.state.time=720.0
	for x in range(38,51):
		for y in range(33,41):world.state.removed[World.key(Vector2i(x,y))]=true
	fresh()
	contract_scenario()
	journey_foundations_first_scenario()
	journey_materials_first_scenario()
	two_players_scenario()
	guard_scenario()
	duplicate_and_overfill_scenario()
	fund_and_q03_scenario()
	reload_scenario()
	legacy_scenario()
	validator_scenario()
	passage_and_fishing_scenario()
	finish()
