extends SceneTree
## Chapter 4 Beimen salt pans through the REAL World.act / World.step /
## World.save / World.load_world path (contract test_salt_pan_world).
##
## SEEDED FIXTURE, NOT NORMAL PLAY (disclosed; each write is labelled `FIXTURE`):
##  * chapter 1 completion (picnic/board/shipped/watered) and a finished chapter-3
##    flower record + completed shared garden (salt letter prerequisite);
##  * travel_book.visited.tianwei (the chapter-3 trip is not replayed);
##  * players are teleported (stand/pose) within reach before actions;
##  * raw backpack stock: plank/resin/stone (gate + kits), copper_ore/wood/fiber
##    (crafted into copper joints and kits at a real bench), wood/stone for the
##    bench/stove/chests, and in the second world machine kits + minnows;
##  * the saturated world seeds 8 private lot holders, repaired gates and the
##    waiting player's first rake.
## EARNED through act()/step(): letter, transit home->tianwei->beimen and back,
## intro, gate donations (incl. the last-gap race), hand flood/rake, rain rules,
## claim, copper joints + both kits crafted at a bench, install, wheel refills,
## wheel-filled hand rake, chest build/config/toggle, automatic deliveries,
## full/invalid/off, fishing minnows, cooking salt_grilled_fish at a stove,
## order, report, note, apprentice shift, graduation, box take, shift expiry.
## World time moves only through World.step(dt, true). Saves go to one fresh
## random TEMP directory; cleanup removes only that directory.
const World=preload("res://scripts/world.gd")
const Salt=preload("res://scripts/salt_pan.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const Shipping=preload("res://scripts/shipping.gd")
const Transit=preload("res://scripts/transit.gd")
const Regions=preload("res://scripts/regions.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const SaveSchema=preload("res://scripts/save_schema.gd")

const A:="tok-salt-alice-SECRET"
const B:="tok-salt-bob-SECRET"
const C:="tok-salt-carol-SECRET"
const STALL:=Vector2i(43,29)
const REJECT:=Salt.REJECT_MESSAGE
const BENCH:=Vector2i(30,42)
const STOVE:=Vector2i(32,42)
const RIVER:=Vector2i(55,36)
const TRACKED:=["sea_salt","plank","resin","stone","salt_wheel_kit","salt_rake_kit","minnow","salt_grilled_fish"]

var checks:=0
var failures:=0
var serial:=0
var dir:=""

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var base:=OS.get_environment("TEMP")
	if base.is_empty():base=OS.get_user_data_dir()
	dir=base.path_join("salt-world-"+Crypto.new().generate_random_bytes(8).hex_encode())
	if DirAccess.dir_exists_absolute(dir):
		expect(false,"refuse to adopt an existing test directory")
		finish()
		return
	DirAccess.make_dir_recursive_absolute(dir)
	test_catalog()
	test_chapter_flow()
	test_saturated_late_joiner()
	test_full_bag_escrow()
	finish()

func finish() -> void:
	if not dir.is_empty() and DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)
	print("SALT_PAN_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)

# ------------------------------------------------------------------ helpers

func act(w,token:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return w.act(token,"sw-%d"%serial,action,p,extra)

func pose(w,token:String,at:Vector2) -> void:
	w.state.players[token].x=at.x # FIXTURE teleport within the current region
	w.state.players[token].y=at.y

## FIXTURE teleport to the nearest standable spot (0.9..2.9 tiles) of `cell`
## in the player's current region.
func stand(w,token:String,cell:Vector2i) -> void:
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
	w.switch_region(Regions.HOME)
	expect(best_d<INF,"standing spot near %s in %s"%[str(cell),region])
	pose(w,token,best)

func inv(w,token:String) -> Dictionary:
	return w.state.players[token].inventory

func held(w,token:String,item:String) -> int:
	return int(inv(w,token).get(item,0))

func rec(w,token:String) -> Dictionary:
	return Salt.own_record(w.state,token)

## Key-order independent bytes (save files sort keys; live dictionaries keep
## insertion order). int/float distinctions are preserved.
func sorted(v):
	if v is Dictionary:
		var keys:Array=v.keys().map(func(x):return str(x))
		keys.sort()
		var out:={}
		for key in keys:out[key]=sorted(v[key])
		return out
	if v is Array:return v.map(func(x):return sorted(x))
	return v

func canon_bytes(v) -> PackedByteArray:
	return var_to_bytes(sorted(v))

func snap(w) -> String:
	return JSON.stringify(w.state)

func salt(w) -> Dictionary:
	return w.state.salt_pan

func beimen_objects(w) -> Dictionary:
	return w.state.regions[Salt.REGION].objects

func k(c:Vector2i) -> String:
	return "%d,%d"%[c.x,c.y]

func new_world(name:String):
	var w=World.new()
	w.save_path=dir.path_join(name+".json")
	return w

func flower_done(w,token:String) -> void:
	var tea:Dictionary=Tea.FRESH.duplicate(true) # FIXTURE finished chapter-2 comparison
	tea.intro=true;tea.potter=true;tea.reused=true;tea.reuse_count=1
	tea.trials={"jar":true,"fiber":true};tea.tea_discussed=true;tea.comparison_complete=true
	w.state.tea_ceramics.players[token]=tea
	var a:Dictionary=Flower.FRESH.duplicate(true) # FIXTURE finished chapter 3
	a.letter=true;a.intro=true;a.shipped=true;a.complete=true
	for kind in Flower.FLOWERS:
		a.planted[kind]=true;a.harvested[kind]=2;a.saved[kind]=true
	w.state.flower_nursery.players[token]=a
	w.state.players[token].travel_book.visited[Flower.REGION]=true

func chapter_one_done(w) -> void:
	w.state.picnic=true # FIXTURE chapter 1 finished (transit requires it)
	w.state.board=true
	w.state.chapter_one.shipped=true
	w.state.chapter_one.watered=true

func garden_done(w,contributors:Dictionary) -> void:
	w.state.flower_nursery.garden={"given":{"blue_dye":4,"orange_blossom":4,"chime_herb":2},"contributors":contributors,"complete":true,"completed_at":0.0} # FIXTURE

## Station-to-station trip through the real transit action.
func travel(w,token:String,destination:String) -> Dictionary:
	var region:String=w.player_region(token)
	var points:Dictionary=Transit.points(region)
	if points.is_empty():return {"ok":false,"message":"no station in "+region}
	var station:String=points.keys()[0]
	var cell:Vector2i=points[station].cell
	stand(w,token,cell)
	return act(w,token,"transit",cell,destination)

func steps(w,seconds:float,chunk:float=60.0) -> bool:
	var left:=seconds
	while left>0.0001:
		var dt:=minf(chunk,left)
		if not w.step(dt,true):return false
		left-=dt
	return true

func step_to(w,time:float,chunk:float=60.0) -> bool:
	return steps(w,time-float(w.state.time),chunk)

## World-wide count of `item`: backpacks, every chest/object in every layer,
## stove jobs/queues (ingredients and pending outputs), gate donations, the
## cooperative box and installed machines.
func total(w,item:String) -> int:
	var n:=0
	for person in w.state.players.values():n+=int(person.inventory.get(item,0))
	var layers:Array=[w.state.objects]
	for region in w.state.regions.values():layers.append(region.objects)
	for layer in layers:
		for obj in layer.values():
			n+=int(obj.get("items",{}).get(item,0))
			if obj.has("job"):
				n+=int(obj.job.get("ingredients",{}).get(item,0))
	var s:Dictionary=salt(w)
	if item in Salt.GATE_MATERIALS:
		for gate in s.gates:n+=int(gate[item])
	if item=="sea_salt":
		for v in s.coop_box.values():n+=int(v)
	var part:=""
	if item=="salt_wheel_kit":part="wheel"
	if item=="salt_rake_kit":part="rake"
	if part!="":
		for lot in s.lots:n+=1 if lot[part] else 0
		n+=1 if s.apprentice[part] else 0
		for box in s.get("kit_box",{}).values():n+=int(box.get(item,0)) # escrowed kits count toward conservation
	return n

func totals(w) -> Dictionary:
	var out:={}
	for item in TRACKED:out[item]=total(w,item)
	return out

## Every sea_salt ever made came from a hand or automatic rake (3 each).
func salt_made(w) -> int:
	var n:=0
	for r in salt(w).players.values():n+=3*(int(r.raked)+int(r.auto_raked))
	return n

func expect_totals(w,expected:Dictionary,label:String) -> void:
	var now:=totals(w)
	for item in expected:
		expect(int(now.get(item,0))==int(expected[item]),"%s: %s total %d == %d"%[label,item,int(now.get(item,0)),int(expected[item])])

func blocked_in(w,region:String,cell:Vector2i) -> bool:
	w.switch_region(region)
	var out:bool=w.blocked(cell)
	w.switch_region(Regions.HOME)
	return out

func socket_cells() -> Array:
	var cells:Array=[]
	for lot in range(Salt.LOT_ORIGINS.size()):
		if lot==Salt.PUBLIC_LOT:continue
		for rect in [Salt.wheel_socket(lot),Salt.rake_socket(lot)]:
			for x in range(rect.position.x,rect.end.x):cells.append(Vector2i(x,rect.position.y))
		for c in Salt.chest_sockets(lot):cells.append(c)
	return cells

func free_home_cell(w,avoid:Array) -> Vector2i:
	for y in range(38,50):
		for x in range(24,52):
			var c:=Vector2i(x,y)
			var key:=k(c)
			if c in avoid or not w.is_land(c) or w.water(c) or w.protected(c) or w.blocked(c) or w.resource(c)!="":continue
			if w.state.crops.has(key) or w.state.objects.has(key) or w.state.ground.has(key) or w.state.roofs.has(key) or w.state.forest.has(key):continue
			return c
	return Vector2i(-1,-1)

## Real fishing at the home river until `token` caught `count` more minnows.
func fish_minnows(w,token:String,count:int) -> void:
	var start:=held(w,token,"minnow")
	stand(w,token,RIVER)
	for i in 16:
		if held(w,token,"minnow")>=start+count:return
		var r:=act(w,token,"fish_start",RIVER)
		expect(r.ok,"cast at the river: "+r.message)
		steps(w,3.5,3.5)
		r=act(w,token,"fish_catch",RIVER)
		expect(r.ok,"catch: "+r.message)
	expect(held(w,token,"minnow")>=start+count,"caught %d minnows"%count)

# ------------------------------------------------------------------ catalog

func test_catalog() -> void:
	for kit in Salt.CRAFT:expect(World.CRAFT.get(kit)==Salt.CRAFT[kit],"World.CRAFT.%s equals SaltPan.CRAFT"%kit)
	expect(World.RECIPES.get("salt_grilled_fish")==Salt.RECIPE.salt_grilled_fish,"World.RECIPES.salt_grilled_fish equals SaltPan.RECIPE")
	expect(World.RECIPES.get("grilled_fish")=={"name":"香煎鯽魚","ingredients":{"carp":1},"time":10.0,"yield":1},"grilled_fish untouched")
	expect(int(World.OTHER_SALES.get("salt_grilled_fish",0))==Salt.SALT_FISH_PRICE and int(World.OTHER_SALES.get("grilled_fish",0))==26,"salt_grilled_fish sells 34, grilled_fish still 26")
	for id in Salt.ITEMS:expect(World.NAMES.get(id)==Salt.ITEMS[id],"World.NAMES.%s equals SaltPan.ITEMS"%id)
	var prices:Dictionary=Shipping.prices(World.CROPS,World.FISH,World.OTHER_SALES)
	expect(not prices.has("sea_salt") and not World.OTHER_SALES.has("sea_salt") and not World.CROPS.has("sea_salt") and not World.FISH.has("sea_salt"),"sea_salt never sellable or shippable")
	for kit in Salt.KITS.values():expect(not prices.has(kit),"%s not shippable"%kit)
	expect(int(prices.get("salt_grilled_fish",0))==34,"salt_grilled_fish shippable at 34")
	expect(World.SALT_GATED==["salt_wheel_kit","salt_rake_kit"],"both kits gated")
	expect(not World.BUILD.has("sea_salt") and not World.BUILD.has("salt_wheel_kit"),"no buildable salt piece (blueprints/undo cannot create kits)")

# ------------------------------------------------------------------ chapter flow

func test_chapter_flow() -> void:
	var w=new_world("flow")
	for t in [A,B,C]:w.add_player(t,t.left(9))
	chapter_one_done(w)
	flower_done(w,A)
	flower_done(w,B)
	garden_done(w,{A:6,B:4})
	expect(Salt.phase(w.state,A)=="letter" and Salt.phase(w.state,C)=="locked","phases before the letter")
	var r:Dictionary
	var before:String

	# --- letter at Xiaoli's stall
	stand(w,C,STALL)
	before=snap(w)
	r=act(w,C,"salt_letter",STALL)
	expect(not r.ok and snap(w)==before,"no letter before chapter 3: "+r.message)
	stand(w,A,Vector2i(20,20))
	r=act(w,A,"salt_letter",STALL)
	expect(not r.ok and r.message.contains("靠近"),"letter needs reach: "+r.message)
	stand(w,A,STALL)
	r=act(w,A,"salt_letter",Vector2i(42,29))
	expect(not r.ok and r.message==World.SALT_HOME_MSG,"letter only at the stall: "+r.message)
	r=act(w,A,"salt_letter",STALL)
	expect(r.ok and rec(w,A).letter,"A receives the letter: "+r.message)
	r=act(w,A,"salt_letter",STALL)
	expect(not r.ok,"letter only once")
	stand(w,B,STALL)
	expect(act(w,B,"salt_letter",STALL).ok,"B receives the letter")
	expect(Salt.phase(w.state,A)=="travel","phase travel after the letter")

	# --- World-level travel home -> tianwei -> beimen, free
	var coins:=int(w.state.players[A].coins)
	w.state.players[C].region=Flower.REGION # FIXTURE C stands at the Tianwei shuttle (no chapter-3 replay)
	w.state.players[C].travel_book.visited[Flower.REGION]=true
	pose(w,C,Vector2(13.5,25.5))
	r=travel(w,C,Salt.REGION)
	expect(not r.ok and w.player_region(C)==Flower.REGION,"beimen closed without the letter: "+r.message)
	for t in [A,B]:
		r=travel(w,t,Flower.REGION)
		expect(r.ok,"%s reaches tianwei: %s"%[t.left(9),r.message])
		r=travel(w,t,Salt.REGION)
		expect(r.ok and w.player_region(t)==Salt.REGION,"%s reaches beimen: %s"%[t.left(9),r.message])
		expect(w.state.players[t].travel_book.visited.get(Salt.REGION)==true,"beimen recorded as visited")
	expect(int(w.state.players[A].coins)==coins,"the first trip costs no coins")
	expect(Vector2(w.state.players[A].x,w.state.players[A].y).distance_to(Salt.ARRIVAL)<4.0,"arrival near the salt bus stop")

	# --- rejection table (nothing changes)
	stand(w,A,Vector2i(14,17))
	inv(w,A).wood=60;inv(w,A).stone=40;inv(w,A).fiber=10 # FIXTURE build stock (untouched by rejections)
	inv(w,A).charcoal=3;inv(w,A).tiller=1;inv(w,A).seeder=1;inv(w,A).harvester=1;inv(w,A).sapling=2
	var at:=Vector2i(14,17)
	var forbidden:={"build_area":"floor|15|17","move_object":"15,17","plant_tree":"","axe":"","pick":"","till_area":"","seed_area":"radish","harvest_area":"",
		"craft":"copper_joint","cook":"soup","queue_cook":"soup","claim_cook":"","cancel_cook":"","cancel_queued_cook":"x","fish_start":"","fish_catch":"",
		"door":"","prepare_material_box":"14,16","hoe":"","seed":"radish","water":"","harvest":"","ship":"","buy":"radish","sell":"wood","donate":"","quest":"aru:0",
		"order":"x","refill_tank":"","toggle_sprinkler":"","mine_copper":"","flower_save":"bluebell"}
	for action in forbidden:
		before=snap(w)
		r=act(w,A,action,at,forbidden[action])
		expect(not r.ok and r.message==REJECT and snap(w)==before,"beimen rejects %s: %s"%[action,r.message])
	for case in [["build",Vector2i(14,16),"bench"],["build",Vector2i(14,17),"chest"],["build",Vector2i(14,16),"floor"],["remove",Vector2i(14,17),""],["build",Vector2i(14,16),"stove"]]:
		before=snap(w)
		r=act(w,A,case[0],case[1],case[2])
		expect(not r.ok and r.message==REJECT and snap(w)==before,"beimen rejects %s %s at %s: %s"%[case[0],case[2],str(case[1]),r.message])
	var raw:={"version":1,"name":"salt","width":1,"height":1,"pieces":[{"kind":"floor","x":0,"y":0}]}
	var quote:Dictionary=w.quote_blueprint(A,raw,Vector2i(14,16),0)
	expect(not quote.get("ok",true) and quote.get("message","")==REJECT,"blueprint staging rejected in beimen: "+str(quote.get("message","")))
	inv(w,A).erase("tiller");inv(w,A).erase("seeder");inv(w,A).erase("harvester");inv(w,A).erase("charcoal");inv(w,A).erase("sapling")
	before=snap(w)
	r=act(w,A,"salt_letter",STALL)
	expect(not r.ok and snap(w)==before,"home-only salt action refused in beimen: "+r.message)

	# --- intro
	stand(w,A,Vector2i(8,14))
	inv(w,A).plank=18;inv(w,A).resin=3;inv(w,A).stone=12 # FIXTURE gate materials (sawmill output not replayed)
	inv(w,B).stone=3 # FIXTURE
	before=snap(w)
	r=act(w,A,"salt_gate_give",Vector2i(8,14),"plank")
	expect(not r.ok and snap(w)==before,"no donation before meeting the salt worker: "+r.message)
	for t in [A,B]:
		stand(w,t,Salt.SALT_WORKER)
		r=act(w,t,"salt_intro",Salt.SALT_WORKER)
		expect(r.ok and rec(w,t).intro,"%s meets the salt worker: %s"%[t.left(9),r.message])
	expect(Salt.phase(w.state,A)=="gates","phase gates")

	# --- gates: donations, flood refused before repair, last-gap race
	var gate_totals:={"plank":total(w,"plank"),"resin":total(w,"resin"),"stone":total(w,"stone")}
	stand(w,A,Vector2i(13,28))
	r=act(w,A,"salt_flood",Salt.pan_rect(16).position)
	expect(not r.ok,"flooding refused before the gates are repaired: "+r.message)
	for g in 3:
		var cell:=Vector2i(8,int(Salt.GATE_ROWS[g])+1)
		stand(w,A,cell)
		for item in ["plank","resin","stone"]:
			if g==2 and item=="stone":continue
			r=act(w,A,"salt_gate_give",cell,item)
			expect(r.ok,"A gives %s to gate %d: %s"%[item,g,r.message])
	expect(held(w,A,"stone")==4 and salt(w).repaired_at==-1.0,"one gap left (gate 2 stone)")
	inv(w,A).stone=2 # FIXTURE keep only 2 stones so B must close the gap (2 stones out of the world)
	gate_totals.stone-=2
	stand(w,A,Vector2i(8,28))
	stand(w,B,Vector2i(8,28))
	r=act(w,A,"salt_gate_give",Vector2i(8,28),"stone")
	expect(r.ok and int(salt(w).gates[2].stone)==2 and held(w,A,"stone")==0,"A gives the 2 stones it has")
	# save failure rolls back B's closing donation, the repair and the event
	var good_path:String=w.save_path
	w.save_path=dir.path_join("missing-dir").path_join("deeper").path_join("world.json")
	before=snap(w)
	var events_before:int=w.state.events.size()
	r=act(w,B,"salt_gate_give",Vector2i(8,28),"stone")
	expect(not r.ok and r.message.contains("保存失敗"),"unwritable save fails the closing donation: "+r.message)
	expect(snap(w)==before and w.state.events.size()==events_before,"save failure rolled back gates, inventory and event")
	w.save_path=good_path
	r=act(w,B,"salt_gate_give",Vector2i(8,28),"stone")
	expect(r.ok and held(w,B,"stone")==1 and int(salt(w).gates[2].stone)==4,"B closes the last gap with only 2 of its 3 stones: "+r.message)
	expect(float(salt(w).repaired_at)==float(w.state.time),"repaired_at set at the closing donation")
	expect((w.island_project_mask() & 8)!=0,"Completed salt gate appears in island news")
	inv(w,A).stone=1 # FIXTURE a late extra stone
	gate_totals.stone+=1
	r=act(w,A,"salt_gate_give",Vector2i(8,28),"stone")
	expect(not r.ok and held(w,A,"stone")==1,"no over-donation once full: "+r.message)
	expect(w.state.events.count(Salt.GATE_EVENT)==1,"repair event broadcast exactly once")
	for item in gate_totals:expect(total(w,item)==int(gate_totals[item]),"%s conserved across donations"%item)
	expect(salt(w).givers.has(A) and salt(w).givers.has(B),"both givers recorded")
	expect(Salt.phase(w.state,A)=="first_salt","phase first_salt")

	# --- manual flood/rake on the public pool (day 0, sunny), rake race
	var pan16:=Salt.pan_rect(16).position
	stand(w,A,pan16)
	stand(w,B,pan16)
	r=act(w,A,"salt_flood",pan16)
	expect(r.ok and salt(w).pans[16].s=="brine" and salt(w).pans[16].f=="hand","A floods the public pan: "+r.message)
	r=act(w,B,"salt_flood",pan16)
	expect(not r.ok,"cannot flood a full pan twice")
	r=act(w,A,"salt_rake",pan16)
	expect(not r.ok and held(w,A,"sea_salt")==0,"no salt before it crystallises: "+r.message)
	expect(steps(w,480.0),"world steps 480 s")
	expect(salt(w).pans[16].s=="salt","pan crystallised after 480 sunny seconds")
	r=w.act(A,"dup-rake","salt_rake",pan16,"")
	expect(r.ok and held(w,A,"sea_salt")==3 and rec(w,A).raked==1,"A rakes 3 salt by hand: "+str(r.message))
	var again:Dictionary=w.act(A,"dup-rake","salt_rake",pan16,"")
	expect(again==r and held(w,A,"sea_salt")==3,"same request id returns the stored receipt without a second rake")
	r=act(w,B,"salt_rake",pan16)
	expect(not r.ok and r.message==Salt.RAKED_MESSAGE and held(w,B,"sea_salt")==0,"B loses the race: "+r.message)
	expect(total(w,"sea_salt")==salt_made(w),"sea_salt conserved after the race")
	r=act(w,B,"salt_flood",pan16)
	expect(r.ok,"B floods the public pan")
	expect(steps(w,480.0),"world steps")
	r=act(w,B,"salt_rake",pan16)
	expect(r.ok and rec(w,B).raked==1,"B rakes by hand")
	expect(Salt.phase(w.state,A)=="claim","phase claim")

	# --- claim
	r=act(w,A,"salt_claim",pan16)
	expect(not r.ok and r.message==Salt.STATUS_TEXT.reserve,"public pool can never be claimed")
	var lot0:=Salt.pan_rect(0).position
	stand(w,A,lot0)
	stand(w,B,lot0)
	r=act(w,A,"salt_claim",lot0)
	expect(r.ok and salt(w).lots[0].owner==A,"A claims lot 0: "+r.message)
	r=act(w,B,"salt_claim",lot0)
	expect(not r.ok and r.message==Salt.CLAIMED_MESSAGE,"B cannot take lot 0")
	var lot1:=Salt.pan_rect(2).position
	stand(w,B,lot1)
	expect(act(w,B,"salt_claim",lot1).ok,"B claims lot 1")
	stand(w,A,Salt.pan_rect(4).position)
	r=act(w,A,"salt_claim",Salt.pan_rect(4).position)
	expect(not r.ok and salt(w).lots[2].owner=="","one lot per player")
	stand(w,A,Salt.pan_rect(2).position)
	r=act(w,A,"salt_flood",Salt.pan_rect(2).position)
	expect(not r.ok,"A cannot flood B's lot: "+r.message)
	expect(Salt.phase(w.state,A)=="wheel","phase wheel")

	# --- back home: bench, copper joints, wheel kit; rake kit gate (plain + sourced)
	r=travel(w,A,Regions.HOME)
	expect(r.ok and w.player_region(A)==Regions.HOME,"A returns home for free: "+r.message)
	inv(w,A).wood=80;inv(w,A).stone=40;inv(w,A).copper_ore=6;inv(w,A).plank=14;inv(w,A).resin=2;inv(w,A).fiber=4 # FIXTURE raw stock
	var bench:=free_home_cell(w,[])
	stand(w,A,bench)
	r=act(w,A,"build",bench,"bench")
	expect(r.ok,"A builds a bench: "+r.message)
	for i in 3:expect(act(w,A,"craft",bench,"copper_joint").ok,"craft copper joint %d"%i)
	r=act(w,A,"craft",bench,"salt_rake_kit")
	expect(not r.ok and r.message==Salt.CRAFT_LOCKED_MESSAGE,"rake kit locked before a wheel-filled rake: "+r.message)
	var wire:="salt_rake_kit|%d,%d|%s|%s"%[bench.x+1,bench.y,"a".repeat(32),"b".repeat(16)]
	before=snap(w)
	r=act(w,A,"craft",bench,wire)
	expect(not r.ok and r.message==Salt.CRAFT_LOCKED_MESSAGE and snap(w)==before,"sourced rake kit locked too: "+r.message)
	r=act(w,A,"craft",bench,"copper_joint|%d,%d|%s|%s"%[bench.x+1,bench.y,"a".repeat(32),"b".repeat(16)])
	expect(not r.ok and r.message!=Salt.CRAFT_LOCKED_MESSAGE,"control: the sourced gate is specific to salt kits")
	# C (no salt record) is locked out of the wheel kit on both paths
	r=travel(w,C,Regions.HOME)
	expect(r.ok,"C returns home")
	stand(w,C,bench)
	inv(w,C).plank=8;inv(w,C).copper_joint=2;inv(w,C).resin=2 # FIXTURE
	before=snap(w)
	r=act(w,C,"craft",bench,"salt_wheel_kit")
	expect(not r.ok and r.message==Salt.CRAFT_LOCKED_MESSAGE and snap(w)==before,"wheel kit locked before a first rake: "+r.message)
	r=act(w,C,"craft",bench,"salt_wheel_kit|%d,%d|%s|%s"%[bench.x+1,bench.y,"c".repeat(32),"d".repeat(16)])
	expect(not r.ok and r.message==Salt.CRAFT_LOCKED_MESSAGE,"sourced wheel kit locked too")
	inv(w,C).erase("plank");inv(w,C).erase("copper_joint");inv(w,C).erase("resin")
	var plank_before:=total(w,"plank")
	r=act(w,A,"craft",bench,"salt_wheel_kit")
	expect(r.ok and held(w,A,"salt_wheel_kit")==1,"A crafts the wheel kit: "+r.message)
	expect(total(w,"plank")==plank_before-8,"wheel kit consumed 8 planks")
	r=travel(w,A,Salt.REGION)
	expect(r.ok,"A returns to beimen (merged, visited): "+r.message)

	# --- install the wheel; collision unchanged
	var collision_before:={}
	for c in socket_cells():collision_before[k(c)]=blocked_in(w,Salt.REGION,c)
	var wheel_cell:=Salt.wheel_socket(0).position
	stand(w,A,wheel_cell)
	r=act(w,A,"salt_install",wheel_cell,"rake")
	expect(not r.ok,"rake cannot go on the wheel socket: "+r.message)
	stand(w,B,Salt.wheel_socket(0).position)
	inv(w,B).salt_wheel_kit=1 # FIXTURE kit for a foreign-install attempt
	r=act(w,B,"salt_install",wheel_cell,"wheel")
	expect(not r.ok and held(w,B,"salt_wheel_kit")==1,"B cannot install on A's lot")
	inv(w,B).erase("salt_wheel_kit")
	r=act(w,A,"salt_install",wheel_cell,"wheel")
	expect(r.ok and salt(w).lots[0].wheel and held(w,A,"salt_wheel_kit")==0,"A installs the wheel: "+r.message)
	for c in socket_cells():expect(blocked_in(w,Salt.REGION,c)==collision_before[k(c)],"collision unchanged at %s"%str(c))
	expect(Salt.phase(w.state,A)=="rake","phase rake")
	var kit_total:=total(w,"salt_wheel_kit")
	expect(kit_total==1,"installed wheel counted once")

	# --- wheel refills (day 0 sunny) and the wheel-filled hand rake
	expect(steps(w,30.0,10.0),"step")
	expect(salt(w).pans[0].s=="brine" and salt(w).pans[0].f=="wheel" and salt(w).pans[1].f=="wheel","wheel filled both empty pans")
	expect(step_to(w,1500.0),"step to day 1")
	expect(salt(w).pans[0].s=="salt" and salt(w).pans[1].s=="salt","wheel-filled pans crystallised")
	stand(w,A,Salt.pan_rect(0).position)
	r=act(w,A,"salt_rake",Salt.pan_rect(0).position)
	expect(r.ok and rec(w,A).wheel_raked==1 and rec(w,A).raked==2,"hand rake of a wheel pan counts as wheel_raked: "+r.message)
	expect(total(w,"sea_salt")==salt_made(w),"sea_salt conserved")

	# --- rain (day 2): flood refused, brine dilutes, salt kept, hand rake works, wheel pauses
	stand(w,B,Salt.pan_rect(17).position)
	expect(step_to(w,2800.0),"step to late day 1")
	r=act(w,B,"salt_flood",Salt.pan_rect(17).position)
	expect(r.ok,"B floods pan 17 on a cloudy day")
	expect(step_to(w,2900.0,20.0),"step into the rain")
	expect(Salt.raining(float(w.state.time)),"day 2 is rainy")
	var v1:Dictionary=Salt.pan_view(salt(w).pans[17],float(w.state.time))
	stand(w,B,Salt.pan_rect(16).position)
	r=act(w,B,"salt_flood",Salt.pan_rect(16).position)
	expect(not r.ok and r.message==Salt.RAIN_FLOOD_MESSAGE,"no flooding in rain: "+r.message)
	expect(steps(w,60.0,20.0),"step in rain")
	var v2:Dictionary=Salt.pan_view(salt(w).pans[17],float(w.state.time))
	expect(v1.diluted and float(v2.ratio)<float(v1.ratio),"brine dilutes in rain (%f -> %f)"%[float(v1.ratio),float(v2.ratio)])
	expect(salt(w).pans[1].s=="salt","formed salt kept under straw mats in rain")
	expect(Salt.pan_view(salt(w).pans[1],float(w.state.time)).covered,"salt shown covered in rain")
	stand(w,A,Salt.pan_rect(1).position)
	r=act(w,A,"salt_rake",Salt.pan_rect(1).position)
	expect(r.ok and rec(w,A).wheel_raked==2,"hand rake works in rain: "+r.message)
	expect(step_to(w,4300.0),"step through the rain")
	expect(salt(w).pans[1].s=="empty","wheel paused: no refill during rain")
	expect(step_to(w,4330.0,10.0),"step past midnight")
	expect(salt(w).pans[1].s=="brine" and float(salt(w).pans[1].t)==4320.0,"wheel refills exactly at the dry midnight")

	# --- rake kit (now allowed), install, chest at socket, cfg, toggle
	r=travel(w,A,Regions.HOME)
	expect(r.ok,"A home again")
	stand(w,A,bench)
	inv(w,A).stone=int(inv(w,A).get("stone",0))+6 # FIXTURE rake-kit stone
	r=act(w,A,"craft",bench,"salt_rake_kit")
	expect(r.ok and held(w,A,"salt_rake_kit")==1,"A crafts the rake kit: "+r.message)
	expect(travel(w,A,Salt.REGION).ok,"A back to beimen")
	var rake_cell:=Salt.rake_socket(0).position
	stand(w,A,rake_cell)
	r=act(w,A,"salt_install",rake_cell,"rake")
	expect(r.ok and salt(w).lots[0].rake,"A installs the collector: "+r.message)
	for c in socket_cells():expect(blocked_in(w,Salt.REGION,c)==collision_before[k(c)],"collision still unchanged at %s"%str(c))
	expect(Salt.status(w.state,A,beimen_objects(w),float(w.state.time)).id=="unset","status unset without a chest")
	var chest_cell:Vector2i=Salt.chest_sockets(0)[0]
	var other_socket:Vector2i=Salt.chest_sockets(0)[1]
	stand(w,B,other_socket)
	inv(w,B).wood=40 # FIXTURE
	before=snap(w)
	r=act(w,B,"build",other_socket,"chest")
	expect(not r.ok and r.message==World.SALT_SOCKET_MSG and snap(w)==before,"only the lot holder builds on its sockets: "+r.message)
	stand(w,A,chest_cell)
	r=act(w,A,"salt_auto_cfg",rake_cell,"%d,%d|6"%[other_socket.x,other_socket.y])
	expect(not r.ok,"cfg needs a chest on the socket: "+r.message)
	r=act(w,A,"build",chest_cell,"chest")
	expect(r.ok and beimen_objects(w).has(k(chest_cell)),"A builds a chest on the socket: "+r.message)
	for c in socket_cells():expect(blocked_in(w,Salt.REGION,c)==collision_before[k(c)] or c==chest_cell,"collision unchanged elsewhere")
	before=snap(w)
	r=act(w,A,"salt_auto_cfg",rake_cell,"%d,%d|2"%[chest_cell.x,chest_cell.y])
	expect(not r.ok and r.message==Salt.CAP_MESSAGE and snap(w)==before and not beimen_objects(w)[k(chest_cell)].has("box_id"),"cap below 3 rejected; the generated box id is rolled back")
	r=act(w,A,"salt_auto_cfg",rake_cell,"%d,%d|6"%[chest_cell.x,chest_cell.y])
	var chest:Dictionary=beimen_objects(w)[k(chest_cell)]
	expect(r.ok and chest.get("box_id") is String and str(chest.box_id).length()==32 and salt(w).lots[0].box==chest.box_id and salt(w).lots[0].cap==6,"cfg links the chest by box id: "+r.message)
	expect(Salt.status(w.state,A,beimen_objects(w),float(w.state.time)).id=="off","status off before enabling")
	r=act(w,A,"salt_auto_toggle",rake_cell)
	expect(r.ok and salt(w).lots[0].on,"collector enabled")

	# --- automation into the chest, full, off, invalid
	expect(step_to(w,5000.0,20.0),"step through a sunny morning")
	chest=beimen_objects(w)[k(chest_cell)]
	expect(int(chest.items.get("sea_salt",0))==6,"two automatic deliveries into the chest (cap 6)")
	expect(rec(w,A).auto_raked==2,"auto_raked counts the deliveries")
	expect(Salt.status(w.state,A,beimen_objects(w),float(w.state.time)).id=="full","status full at cap")
	expect(Salt.phase(w.state,A)=="order","phase order after automation")
	expect(steps(w,600.0),"more time while full")
	expect(int(beimen_objects(w)[k(chest_cell)].items.get("sea_salt",0))==6 and salt(w).pans[0].s=="salt","full chest: salt waits in the pan")
	expect(total(w,"sea_salt")==salt_made(w),"sea_salt conserved through automation")
	expect(act(w,A,"salt_auto_toggle",rake_cell).ok and Salt.status(w.state,A,beimen_objects(w),float(w.state.time)).id=="off","status off")
	for i in 6:expect(act(w,A,"withdraw",chest_cell,"sea_salt").ok,"withdraw salt %d"%i)
	r=act(w,A,"remove",chest_cell)
	expect(r.ok and not beimen_objects(w).has(k(chest_cell)),"empty chest removed from the socket: "+r.message)
	expect(act(w,A,"salt_auto_toggle",rake_cell).ok,"toggle on with the chest gone")
	expect(Salt.status(w.state,A,beimen_objects(w),float(w.state.time)).id=="invalid","status invalid without the chest")
	var made:=salt_made(w)
	expect(steps(w,300.0),"step while invalid")
	expect(salt_made(w)==made and total(w,"sea_salt")==made,"invalid chest: nothing delivered, nothing lost")
	expect(act(w,A,"build",chest_cell,"chest").ok,"rebuild a chest")
	expect(Salt.status(w.state,A,beimen_objects(w),float(w.state.time)).id=="invalid","a new chest is not silently adopted")
	expect(act(w,A,"salt_auto_toggle",rake_cell).ok and act(w,A,"salt_auto_cfg",rake_cell,"%d,%d|60"%[chest_cell.x,chest_cell.y]).ok and act(w,A,"salt_auto_toggle",rake_cell).ok,"re-link the new chest")
	expect(steps(w,60.0,20.0),"step")
	expect(int(beimen_objects(w)[k(chest_cell)].items.get("sea_salt",0))>=3,"deliveries resume into the new chest")
	expect(total(w,"sea_salt")==salt_made(w),"sea_salt conserved")

	# --- SaltPan.step ok:false fails the WHOLE World.step atomically.
	# FAULT-INJECTION FIXTURE, not gameplay: an invalid pan state ("mud", which
	# valid() rejects on load) deterministically forces SaltPan.step ok:false.
	# MAX_EVENTS is not reached by valid caps here; this only proves propagation.
	var saved_pan:Dictionary=salt(w).pans[3].duplicate(true)
	salt(w).pans[3].s="mud" # FAULT injection
	var world_before:Dictionary=w.state.duplicate(true)
	var json_before:=JSON.stringify(w.state)
	var file_before:=FileAccess.get_file_as_string(w.save_path)
	var t_before:=float(w.state.time)
	expect(not w.step(30.0,true),"World.step returns false on a rejected salt step")
	expect(w.state==world_before and JSON.stringify(w.state)==json_before,"rejected tick: full world snapshot restored (time, committed, regions, inventories, chests, undo)")
	expect(float(w.state.time)==t_before and w.step_error==World.STEP_FAIL_SALT,"rejected tick: time not advanced, salt failure reported")
	expect(w._region==Regions.HOME and w._undo_used.is_empty(),"rejected tick: HOME projection, no undo scratch")
	expect(FileAccess.get_file_as_string(w.save_path)==file_before and not FileAccess.file_exists(w.save_path+".tmp"),"rejected tick: no durable save")
	salt(w).pans[3]=saved_pan # undo FAULT injection
	expect(w.step(30.0,true) and float(w.state.time)==t_before+30.0 and w.step_error=="","repaired pan: the next tick advances normally")

	# --- cook salt_grilled_fish (real fishing + stove), order once
	expect(travel(w,A,Regions.HOME).ok,"A home for the order")
	fish_minnows(w,A,2)
	var stove:=free_home_cell(w,[bench])
	stand(w,A,stove)
	expect(act(w,A,"build",stove,"stove").ok,"A builds a stove")
	# Automation keeps running in beimen while A cooks, so sea_salt is checked
	# against everything ever raked minus what cooking/the order consumed.
	var tracked:={"minnow":total(w,"minnow"),"salt_grilled_fish":total(w,"salt_grilled_fish")}
	var consumed:=0
	expect(total(w,"sea_salt")==salt_made(w)-consumed,"sea_salt before cooking")
	for i in 2:
		r=act(w,A,"cook",stove,"salt_grilled_fish")
		expect(r.ok,"cook salt_grilled_fish: "+r.message)
		expect_totals(w,tracked,"cooking in progress")
		expect(total(w,"sea_salt")==salt_made(w)-consumed,"sea_salt held by the stove job")
		steps(w,15.0,15.0)
		r=act(w,A,"claim_cook",stove)
		expect(r.ok,"claim salt_grilled_fish: "+r.message)
		tracked.minnow-=1;tracked.salt_grilled_fish+=1;consumed+=1
		expect_totals(w,tracked,"after cooking")
		expect(total(w,"sea_salt")==salt_made(w)-consumed,"one sea_salt consumed per dish")
	expect(held(w,A,"salt_grilled_fish")==2 and w.state.players[A].collection.meals.has("salt_grilled_fish"),"two salt-grilled fish, recorded as a meal")
	stand(w,A,STALL)
	before=snap(w)
	r=act(w,A,"sell",STALL,"sea_salt")
	expect(not r.ok and snap(w)==before,"sea salt cannot be sold: "+r.message)
	r=act(w,A,"buy",STALL,"sea_salt")
	expect(not r.ok and snap(w)==before,"sea salt cannot be bought: "+r.message)
	coins=int(w.state.players[A].coins)
	var salt_held:=held(w,A,"sea_salt")
	r=act(w,A,"salt_order",STALL)
	expect(r.ok and int(w.state.players[A].coins)==coins+120 and held(w,A,"sea_salt")==salt_held-4 and held(w,A,"salt_grilled_fish")==0,"order pays 120: "+r.message)
	r=act(w,A,"salt_order",STALL)
	expect(not r.ok and int(w.state.players[A].coins)==coins+120,"order pays only once")
	expect(Salt.phase(w.state,A)=="report","phase report")
	consumed+=4
	expect(total(w,"sea_salt")==salt_made(w)-consumed,"order consumed exactly 4 sea_salt")

	# --- report + note
	expect(travel(w,A,Salt.REGION).ok,"A back to beimen")
	stand(w,A,Salt.SALT_WORKER)
	r=act(w,A,"salt_report",Salt.SALT_WORKER)
	expect(r.ok and rec(w,A).complete and Salt.phase(w.state,A)=="complete","report completes the chapter: "+r.message)
	stand(w,A,Salt.HERITAGE_SIGN)
	r=act(w,A,"salt_note",Salt.HERITAGE_SIGN)
	expect(r.ok and rec(w,A).note and r.message==Salt.NOTE_TEXT,"heritage note readable, gives nothing")

	# --- save -> load -> identical progress (also after the same further steps)
	expect(w.save(),"world saves")
	var loaded=World.new()
	expect(loaded.load_world(w.save_path) and not loaded.recovered_from_backup,"saved salt world reloads")
	# The loader adds unrelated defaults (community, fish_caught) and save files
	# sort keys, so compare against the live state passed through the same schema.
	var expected=JSON.parse_string(JSON.stringify(w.state))
	expect(SaveSchema.validate(expected,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"live state validates")
	expect(canon_bytes(loaded.state)==canon_bytes(expected),"reloaded state identical to the validated live state")
	expect(canon_bytes(loaded.state.salt_pan)==canon_bytes(w.state.salt_pan),"salt_pan bytes identical after reload (types kept)")
	var other_path:String=dir.path_join("flow-copy.json")
	loaded.save_path=other_path
	for world in [w,loaded]:steps(world,1800.0,60.0)
	expect(canon_bytes(loaded.state.salt_pan)==canon_bytes(w.state.salt_pan),"identical salt progress after restart + same steps")
	expect(JSON.stringify(loaded.state.regions[Salt.REGION].objects)==JSON.stringify(w.state.regions[Salt.REGION].objects),"identical chest contents after restart")

# ------------------------------------------------------------------ late joiner

func test_saturated_late_joiner() -> void:
	var w=new_world("saturated")
	chapter_one_done(w)
	var tokens:Array=[]
	var contributors:={}
	for i in 10:
		var t:="tok-salt-p%d-SECRET"%i
		tokens.append(t)
		w.add_player(t,"p%d"%i)
		flower_done(w,t)
		contributors[t]=1
	garden_done(w,contributors)
	var s:Dictionary=salt(w)
	# FIXTURE: gates repaired, every player met the salt worker in beimen, 8 lot holders.
	for g in 3:s.gates[g]=Salt.GATE_NEEDS_EACH.duplicate(true)
	s.givers[tokens[0]]=true
	s.repaired_at=0.0
	for i in 10:
		var t:String=tokens[i]
		var record:Dictionary=Salt.RECORD.duplicate(true)
		record.letter=true;record.intro=true
		if i<8 or i==9:record.raked=1
		s.players[t]=record
		var p:Dictionary=w.state.players[t]
		p.region=Salt.REGION
		p.travel_book.visited[Salt.REGION]=true
		pose(w,t,Salt.ARRIVAL)
		if i<8:s.lots[i].owner=t
	var lots_before:=JSON.stringify(s.lots)
	var seeded_salt:=salt_made(w) # FIXTURE raked counts carry no salt into this world
	var late:String=tokens[8]
	var waiting:String=tokens[9]
	expect(Salt.free_lots(w.state)==0,"all 8 private lots are taken")
	# late joiner: manual first salt on the public pool
	var pan16:=Salt.pan_rect(16).position
	stand(w,late,pan16)
	var r:=act(w,late,"salt_flood",pan16)
	expect(r.ok,"late joiner floods the public pool: "+r.message)
	expect(steps(w,480.0),"step")
	r=act(w,late,"salt_rake",pan16)
	expect(r.ok and rec(w,late).raked==1,"late joiner rakes by hand")
	expect(Salt.craft_allowed(w.state,late,"salt_wheel_kit") and not Salt.craft_allowed(w.state,late,"salt_rake_kit"),"late joiner may craft the wheel kit only")
	stand(w,late,Salt.pan_rect(0).position)
	r=act(w,late,"salt_claim",Salt.pan_rect(0).position)
	expect(not r.ok and r.message==Salt.CLAIMED_MESSAGE,"no private lot free")
	var app_pan:=Salt.pan_rect(18).position
	stand(w,late,app_pan)
	r=act(w,late,"salt_claim",app_pan)
	expect(r.ok and salt(w).apprentice.tenant==late,"late joiner takes the apprentice shift: "+r.message)
	stand(w,waiting,app_pan)
	r=act(w,waiting,"salt_claim",app_pan)
	expect(r.ok and r.message.begins_with("學徒區正由另一位島民輪班") and Salt.queue_position(w.state,waiting)==1,"10th player waits in the fair list: "+r.message)
	r=act(w,waiting,"salt_flood",app_pan)
	expect(not r.ok,"only the tenant works apprentice pans")
	# apprentice machines (kits: FIXTURE; the real craft path is covered by test_chapter_flow)
	inv(w,late).salt_wheel_kit=1;inv(w,late).salt_rake_kit=1
	var kits:=total(w,"salt_wheel_kit")+total(w,"salt_rake_kit")
	var wheel9:=Salt.wheel_socket(Salt.APPRENTICE_LOT).position
	stand(w,late,wheel9)
	r=act(w,late,"salt_install",wheel9,"wheel")
	expect(r.ok and salt(w).apprentice.wheel,"wheel on the apprentice station: "+r.message)
	expect(steps(w,500.0),"wheel cycle")
	stand(w,late,app_pan)
	r=act(w,late,"salt_rake",app_pan)
	expect(r.ok and rec(w,late).wheel_raked==1,"tenant hand-rakes a wheel pan: "+r.message)
	var rake9:=Salt.rake_socket(Salt.APPRENTICE_LOT).position
	stand(w,late,rake9)
	expect(act(w,late,"salt_install",rake9,"rake").ok,"collector on the apprentice station")
	r=act(w,late,"salt_auto_cfg",rake9,"14,16|6")
	expect(not r.ok,"apprentice cfg must name the cooperative chest: "+r.message)
	r=act(w,late,"salt_auto_cfg",rake9,"%d,%d|6"%[Salt.APPRENTICE_CHEST.x,Salt.APPRENTICE_CHEST.y])
	expect(r.ok and salt(w).apprentice.cap==6,"apprentice cfg: "+r.message)
	expect(act(w,late,"salt_auto_toggle",rake9).ok and salt(w).apprentice.on,"apprentice collector on")
	expect(total(w,"salt_wheel_kit")+total(w,"salt_rake_kit")==kits,"kits conserved while installed")
	expect(steps(w,600.0),"automation")
	expect(int(salt(w).coop_box.get(late,0))==3 and rec(w,late).auto_raked==1,"first automatic delivery into the cooperative box")
	expect(salt(w).apprentice.tenant=="" and held(w,late,"salt_wheel_kit")==1 and held(w,late,"salt_rake_kit")==1,"graduation returns both kits")
	expect(total(w,"salt_wheel_kit")+total(w,"salt_rake_kit")==kits,"kits conserved across graduation")
	for i in [18,19]:expect(salt(w).pans[i].f in ["","hand"],"apprentice pan %d no longer credits the wheel"%i)
	expect(JSON.stringify(salt(w).lots)==lots_before,"private lots untouched by the apprentice path")
	stand(w,waiting,Salt.APPRENTICE_CHEST)
	r=act(w,waiting,"salt_box_take",Salt.APPRENTICE_CHEST)
	expect(not r.ok and int(salt(w).coop_box.get(late,0))==3,"others cannot take the compartment")
	stand(w,late,Salt.APPRENTICE_CHEST)
	var sea:=held(w,late,"sea_salt")
	r=act(w,late,"salt_box_take",Salt.APPRENTICE_CHEST)
	expect(r.ok and held(w,late,"sea_salt")==sea+3 and not salt(w).coop_box.has(late),"salt_box_take moves the compartment: "+r.message)
	expect(total(w,"sea_salt")==salt_made(w)-seeded_salt,"sea_salt conserved on the apprentice path")
	# 10th player: shift, expiry, kit returned, re-take
	stand(w,waiting,app_pan)
	r=act(w,waiting,"salt_claim",app_pan)
	expect(r.ok and salt(w).apprentice.tenant==waiting,"10th player takes the free shift: "+r.message)
	inv(w,waiting).salt_wheel_kit=1 # FIXTURE
	stand(w,waiting,wheel9)
	expect(act(w,waiting,"salt_install",wheel9,"wheel").ok,"10th installs a wheel")
	var since:=float(salt(w).apprentice.since)
	expect(step_to(w,since+Salt.SHIFT_SECONDS-60.0,120.0),"step near the end of the shift")
	expect(salt(w).apprentice.tenant==waiting,"shift still running before expiry")
	expect(step_to(w,since+Salt.SHIFT_SECONDS+60.0,60.0),"step past expiry")
	expect(salt(w).apprentice.tenant=="" and held(w,waiting,"salt_wheel_kit")==1,"expiry returns the kit")
	expect(rec(w,waiting).raked>=1,"expiry keeps progress")
	stand(w,waiting,app_pan)
	expect(act(w,waiting,"salt_claim",app_pan).ok,"the same player may take an empty shift again")
	# late joiner: order and report
	expect(travel(w,late,Regions.HOME).ok,"late joiner travels home")
	inv(w,late).minnow=2;inv(w,late).wood=12;inv(w,late).stone=15 # FIXTURE minnows + stove stock
	var stove:=free_home_cell(w,[])
	stand(w,late,stove)
	expect(act(w,late,"build",stove,"stove").ok,"stove")
	for i in 2:
		expect(act(w,late,"cook",stove,"salt_grilled_fish").ok,"cook")
		steps(w,15.0,15.0)
		expect(act(w,late,"claim_cook",stove).ok,"claim")
	stand(w,late,STALL)
	expect(held(w,late,"sea_salt")>=4,"enough salt for the order")
	r=act(w,late,"salt_order",STALL)
	expect(r.ok,"late joiner completes the order: "+r.message)
	expect(travel(w,late,Salt.REGION).ok,"back to beimen")
	stand(w,late,Salt.SALT_WORKER)
	r=act(w,late,"salt_report",Salt.SALT_WORKER)
	expect(r.ok and rec(w,late).complete,"late joiner completes the chapter: "+r.message)
	expect(w.save(),"saturated world saves")
	var loaded=World.new()
	expect(loaded.load_world(w.save_path),"saturated world reloads")

# ------------------------------------------------------------------ full-bag escrow

## Seeds the same saturated beimen as test_saturated_late_joiner (FIXTURE:
## finished chapters, repaired gates, 8 lot holders, one hand rake each).
func saturated_world(name:String,prefix:String) -> Array:
	var w=new_world(name)
	chapter_one_done(w)
	var tokens:Array=[]
	var contributors:={}
	for i in 10:
		var t:="tok-salt-%s%d-SECRET"%[prefix,i]
		tokens.append(t)
		w.add_player(t,"%s%d"%[prefix,i])
		flower_done(w,t)
		contributors[t]=1
	garden_done(w,contributors)
	var s:Dictionary=salt(w)
	for g in 3:s.gates[g]=Salt.GATE_NEEDS_EACH.duplicate(true) # FIXTURE
	s.givers[tokens[0]]=true
	s.repaired_at=0.0
	for i in 10:
		var t:String=tokens[i]
		var record:Dictionary=Salt.RECORD.duplicate(true) # FIXTURE met the salt worker, raked once by hand
		record.letter=true;record.intro=true;record.raked=1
		s.players[t]=record
		var p:Dictionary=w.state.players[t]
		p.region=Salt.REGION
		p.travel_book.visited[Salt.REGION]=true
		pose(w,t,Salt.ARRIVAL)
		if i<8:s.lots[i].owner=t # FIXTURE lot holders
	return [w,tokens]

## Same reload comparison as test_chapter_flow: live state through the schema
## vs the reloaded world; salt_pan, every inventory and the beimen chests.
func expect_reload(w,label:String):
	expect(w.save(),"%s: world saves"%label)
	var loaded=World.new()
	expect(loaded.load_world(w.save_path) and not loaded.recovered_from_backup,"%s: load_world into a new World"%label)
	var expected=JSON.parse_string(JSON.stringify(w.state))
	expect(SaveSchema.validate(expected,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"%s: live state validates"%label)
	expect(canon_bytes(loaded.state)==canon_bytes(expected),"%s: reloaded state identical to the validated live state"%label)
	expect(canon_bytes(loaded.state.salt_pan)==canon_bytes(w.state.salt_pan),"%s: salt_pan identical (escrow, list, cooperative box)"%label)
	for t in w.state.players:
		expect(canon_bytes(loaded.state.players[t].inventory)==canon_bytes(w.state.players[t].inventory),"%s: inventory identical for %s"%[label,str(t).left(12)])
	expect(canon_bytes(loaded.state.regions[Salt.REGION].objects)==canon_bytes(w.state.regions[Salt.REGION].objects),"%s: beimen chests identical"%label)
	expect(totals(loaded)==totals(w),"%s: item totals identical after reload"%label)
	return loaded

## The tenant's bag is at LIMIT for the wheel kit when the shift expires: the
## shift still ends exactly on time, the wheel goes to the tenant's escrow, the
## waiting player is offered and takes the shift, and the tenant later takes the
## escrow back with salt_box_take. Every salt action goes through World.act and
## time only through World.step.
func test_full_bag_escrow() -> void:
	var seeded:Array=saturated_world("escrow","e")
	var w=seeded[0]
	var tokens:Array=seeded[1]
	var tenant:String=tokens[8]
	var waiter:String=tokens[9]
	var app_pan:=Salt.pan_rect(18).position
	var wheel9:=Salt.wheel_socket(Salt.APPRENTICE_LOT).position
	var rake9:=Salt.rake_socket(Salt.APPRENTICE_LOT).position
	var r:Dictionary
	stand(w,tenant,app_pan)
	r=act(w,tenant,"salt_claim",app_pan)
	expect(r.ok and salt(w).apprentice.tenant==tenant,"tenant takes the apprentice shift: "+r.message)
	var since:=float(salt(w).apprentice.since)
	stand(w,waiter,app_pan)
	r=act(w,waiter,"salt_claim",app_pan)
	expect(r.ok and Salt.queue_position(w.state,waiter)==1,"waiting player joins the fair list: "+r.message)
	inv(w,tenant).salt_wheel_kit=1;inv(w,tenant).salt_rake_kit=1 # FIXTURE kits (real craft path: test_chapter_flow)
	stand(w,tenant,wheel9)
	r=act(w,tenant,"salt_install",wheel9,"wheel")
	expect(r.ok and salt(w).apprentice.wheel,"wheel installed on the station: "+r.message)
	stand(w,tenant,rake9)
	r=act(w,tenant,"salt_install",rake9,"rake")
	expect(r.ok and salt(w).apprentice.rake and not salt(w).apprentice.on,"collector installed, left off (no graduation): "+r.message)
	# FIXTURE LIMIT inventories (the only practical way to reach LIMIT): the bag
	# already holds LIMIT wheel kits and LIMIT-1 rake kits.
	inv(w,tenant).salt_wheel_kit=Salt.LIMIT
	inv(w,tenant).salt_rake_kit=Salt.LIMIT-1
	var kits:={"salt_wheel_kit":total(w,"salt_wheel_kit"),"salt_rake_kit":total(w,"salt_rake_kit")}
	expect(int(kits.salt_wheel_kit)==Salt.LIMIT+1 and int(kits.salt_rake_kit)==Salt.LIMIT,"kit totals include the installed machines")
	var tracked:=totals(w)
	stand(w,tenant,rake9)
	r=act(w,tenant,"salt_uninstall",rake9,"rake")
	expect(r.ok and held(w,tenant,"salt_rake_kit")==Salt.LIMIT,"control: a rake kit still fits (LIMIT-1 -> LIMIT): "+r.message)
	r=act(w,tenant,"salt_install",rake9,"rake")
	expect(r.ok and held(w,tenant,"salt_rake_kit")==Salt.LIMIT-1,"rake reinstalled: "+r.message)
	expect_totals(w,tracked,"uninstall/reinstall")
	# --- run the shift out through World.step
	expect(step_to(w,since+Salt.SHIFT_SECONDS-30.0,600.0),"step to 30 s before the shift ends")
	expect(salt(w).apprentice.tenant==tenant and salt(w).kit_box.is_empty(),"shift still running, escrow empty")
	expect(steps(w,60.0,60.0) and w.step_error=="","the expiring tick succeeds (no deferral, no rollback)")
	expect(salt(w).apprentice.tenant=="" and not salt(w).apprentice.wheel and not salt(w).apprentice.rake,"shift ended exactly on time with a full bag")
	expect(salt(w).kit_box.get(tenant)=={"salt_wheel_kit":1,"salt_rake_kit":0},"wheel kit that did not fit went to the escrow of the tenant: %s"%str(salt(w).kit_box.get(tenant)))
	expect(held(w,tenant,"salt_wheel_kit")==Salt.LIMIT and held(w,tenant,"salt_rake_kit")==Salt.LIMIT,"rake kit still fit the bag; nothing exceeds LIMIT")
	expect(salt(w).kit_box.size()==1,"no other escrow touched")
	expect(float(salt(w).waitlist.offer_at)==since+Salt.SHIFT_SECONDS and salt(w).waitlist.order[0].token==waiter,"window of the waiting player opens at the exact end instant")
	for i in [18,19]:expect(salt(w).pans[i].f in ["","hand"],"apprentice pan %d gives no wheel credit"%i)
	expect_totals(w,tracked,"after expiry (escrow counted)")
	var objs:Dictionary=beimen_objects(w)
	var now:=float(w.state.time)
	var view_t:Dictionary=Salt.own_view(w.state,tenant,objs,now)
	var view_w:Dictionary=Salt.own_view(w.state,waiter,objs,now)
	expect(view_t.apprentice.kits=={"salt_wheel_kit":1,"salt_rake_kit":0} and not view_t.apprentice.offer,"tenant sees own escrow, no offer")
	expect(view_w.apprentice.offer and view_w.apprentice.kits=={"salt_wheel_kit":0,"salt_rake_kit":0},"waiting player is offered the shift and sees no foreign escrow")
	# --- save -> load_world into a new World -> identical; continue on the reloaded world
	var w2=expect_reload(w,"escrow at expiry")
	w2.save_path=dir.path_join("escrow-reloaded.json")
	expect_totals(w2,tracked,"reloaded world")
	# Ex-tenant cannot jump the list: joins behind the offered player.
	stand(w2,tenant,app_pan)
	r=act(w2,tenant,"salt_claim",app_pan)
	expect(r.ok and salt(w2).apprentice.tenant=="" and Salt.queue_position(w2.state,tenant)==2,"ex-tenant rejoins at the back: "+r.message)
	# Escrow cannot be taken while the bag is full for that kit: refused, unchanged.
	stand(w2,tenant,Salt.APPRENTICE_CHEST)
	var before:=snap(w2)
	r=act(w2,tenant,"salt_box_take",Salt.APPRENTICE_CHEST)
	expect(not r.ok and snap(w2)==before,"box take with a full bag is refused and changes nothing: "+r.message)
	stand(w2,waiter,app_pan)
	r=act(w2,waiter,"salt_claim",app_pan)
	expect(r.ok and salt(w2).apprentice.tenant==waiter and salt(w2).waitlist.order.size()==1 and float(salt(w2).waitlist.offer_at)==0.0,"waiting player takes the offered shift: "+r.message)
	stand(w2,waiter,Salt.APPRENTICE_CHEST)
	before=snap(w2)
	r=act(w2,waiter,"salt_box_take",Salt.APPRENTICE_CHEST)
	expect(not r.ok and snap(w2)==before and salt(w2).kit_box.get(tenant)=={"salt_wheel_kit":1,"salt_rake_kit":0},"others cannot take the escrow of the tenant: "+r.message)
	expect(steps(w2,120.0,60.0),"time passes during the new shift")
	stand(w2,waiter,app_pan)
	r=act(w2,waiter,"salt_release",app_pan)
	expect(r.ok and salt(w2).apprentice.tenant=="" and salt(w2).waitlist.order[0].token==tenant and float(salt(w2).waitlist.offer_at)==float(w2.state.time),"voluntary release offers the station to the next in line: "+r.message)
	stand(w2,tenant,app_pan)
	r=act(w2,tenant,"salt_claim",app_pan)
	expect(r.ok and salt(w2).apprentice.tenant==tenant and salt(w2).waitlist.order.is_empty(),"former tenant takes the next shift in turn: "+r.message)
	stand(w2,tenant,wheel9)
	r=act(w2,tenant,"salt_install",wheel9,"wheel")
	expect(r.ok and held(w2,tenant,"salt_wheel_kit")==Salt.LIMIT-1,"installing a wheel from the bag frees one slot: "+r.message)
	stand(w2,tenant,Salt.APPRENTICE_CHEST)
	r=act(w2,tenant,"salt_box_take",Salt.APPRENTICE_CHEST)
	expect(r.ok and held(w2,tenant,"salt_wheel_kit")==Salt.LIMIT and not salt(w2).kit_box.has(tenant),"salt_box_take returns the escrowed wheel kit: "+r.message)
	expect(Salt.escrow_of(w2.state,tenant)=={"salt_wheel_kit":0,"salt_rake_kit":0},"escrow emptied")
	expect_totals(w2,tracked,"after the escrow take")
	expect(int(total(w2,"salt_wheel_kit"))==Salt.LIMIT+1 and int(total(w2,"salt_rake_kit"))==Salt.LIMIT,"kits conserved end to end (bag + installed + escrow)")
	var w3=expect_reload(w2,"after escrow take")
	expect(salt(w3).apprentice.tenant==tenant and salt(w3).kit_box.is_empty(),"final reload keeps the shift and the empty escrow")
