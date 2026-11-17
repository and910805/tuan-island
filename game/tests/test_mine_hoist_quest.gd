extends SceneTree
## T067 Q07 「卡住的升降台」 + glass furnace + deep-mine quest sources, through
## real World.act() actions (receipts, rollback and save included).
##
## PRESETS (fixture inputs, not earned in play; the earned path lives in
## test_mine_deep_journey):
##  * main world: state.picnic=true; mine_depths starts at
##    {"unlocked":5,"ready":{},"pumped":24,"hoist":false} and is later set to
##    unlocked 6 (the B5 commission itself is covered by test_mine_deep_levels);
##  * owner bag is replaced by exactly {copper_joint 12, plank 4, stone 25,
##    iron_ingot 6, crystal_sand 3, wood 1, vein_quartz 2} (= HOIST_COST + the
##    glass_furnace cost + one glass job + one crystal_sand job);
##  * other bag is replaced by exactly HOIST_COST (used to prove a second repair
##    is refused and charges nothing);
##  * players are relocated between the jinguashi surface, mine_1, mine_6 and home
##    by writing region/x/y (walking is covered by the journey suites);
##  * legacy fixtures: fresh worlds whose mine_depths is the pre-Q07 three-key
##    shape {"unlocked":5|9,"ready":{},"pumped":24}, written to TEMP as JSON;
##  * mining world (never saved): unlocked 9, hoist false, owner bag
##    {reinforced_pick 1}, relocated to mine_6 then mine_9.
## World time only moves through explicit World.step(dt,true) calls.
const World=preload("res://scripts/world.gd")
const Mines=preload("res://scripts/mine_depths.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Sources=preload("res://scripts/material_sources.gd")
const Rooms=preload("res://scripts/house_rooms.gd")
const OWNER:="hoist-owner"
const OTHER:="hoist-other"
const SURFACE:="jinguashi"
const SURFACE_ARRIVAL:=Vector2(27.5,19.5)
const TILE:=Vector2i(38,34)
const CLOSED:="此礦道尚未開放，或你離入口太遠。"
const WRONG_PLACE:="請到金瓜石合作礦場的下坑路牌。"
const FURNACE_COST:={"stone":25,"iron_ingot":6}
var checks:=0
var failures:=0
var serial:=0
var temp_files:Array=[]

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)
	return ok

func rid(tag:String)->String:
	serial+=1
	return "%s-%d"%[tag,serial]

func valid(data:Dictionary)->bool:
	return Schema.validate(data,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

## Canonical bag: String keys, int values, zero entries dropped.
static func canon(inv:Dictionary)->Dictionary:
	var out:={}
	for item in inv:
		if int(inv[item])!=0:out[str(item)]=int(inv[item])
	return out

static func adjusted(before:Dictionary,delta:Dictionary)->Dictionary:
	var out:=canon(before)
	for item in delta:
		var amount:=int(out.get(str(item),0))+int(delta[item])
		if amount==0:out.erase(str(item))
		else:out[str(item)]=amount
	return out

static func negated(cost:Dictionary)->Dictionary:
	var out:={}
	for item in cost:out[item]=-int(cost[item])
	return out

func bag(w:World,who:String)->Dictionary:
	return w.state.players[who].inventory

func relocate(w:World,who:String,region:String,at:Vector2)->void:
	var person:Dictionary=w.state.players[who]
	person["region"]=region
	person["x"]=at.x
	person["y"]=at.y

func place(w:World,who:String,p:Vector2i)->void:
	w.state.players[who]["x"]=p.x-0.5
	w.state.players[who]["y"]=p.y+0.5

func act(w:World,who:String,action:String,p:Vector2i,extra:String="",request:String="")->Dictionary:
	place(w,who,p)
	return w.act(who,request if not request.is_empty() else rid(action),action,p,extra)

## Exact message, whole state (and so the whole bag) unchanged.
func refuse(w:World,who:String,action:String,p:Vector2i,extra:String,message:String,label:String)->void:
	place(w,who,p)
	var before:=w.state.duplicate(true)
	var bag_before:=canon(bag(w,who))
	var result:=w.act(who,rid("refuse"),action,p,extra)
	expect(not result.ok and str(result.message)==message,"%s: '%s' (got ok=%s '%s')"%[label,message,str(result.ok),str(result.message)])
	expect(w.state==before and canon(bag(w,who))==bag_before,label+": whole state and inventory unchanged")

func refuse_prefix(w:World,who:String,action:String,p:Vector2i,prefix:String,label:String)->void:
	place(w,who,p)
	var before:=w.state.duplicate(true)
	var result:=w.act(who,rid("refuse"),action,p,"")
	expect(not result.ok and str(result.message).begins_with(prefix),"%s: starts with '%s' (got '%s')"%[label,prefix,str(result.message)])
	expect(w.state==before,label+": whole state unchanged")

func temp_path(tag:String)->String:
	var path:=OS.get_environment("TEMP").path_join("hoist-quest-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(6).hex_encode()])
	for suffix in ["",".bak",".tmp"]:temp_files.append(path+suffix)
	return path

func _initialize()->void:
	check_static()
	var path:=temp_path("main")
	var w:=World.new()
	w.save_path=path
	w.add_player(OWNER,"Owner")
	w.add_player(OTHER,"Other")
	check_fresh(w)
	check_quest(w,path)
	check_legacy_and_validation()
	check_mining()
	if failures==0:
		for file_path in temp_files:
			if FileAccess.file_exists(file_path):DirAccess.remove_absolute(file_path)
	print("MINE_HOIST_QUEST_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func check_static()->void:
	expect(Mines.HOIST_COST=={"copper_joint":12,"plank":4},"HOIST_COST is 12 copper joints + 4 planks")
	expect(Mines.fresh()=={"unlocked":1,"ready":{},"pumped":0,"hoist":false},"fresh mine progress has a stuck hoist")
	expect(not Mines.hoist_ready({"unlocked":15,"ready":{},"pumped":24}) and Mines.hoist_ready({"unlocked":6,"ready":{},"pumped":24,"hoist":true}),"hoist_ready reads the hoist flag only")
	expect(Mines.surface_landings({"unlocked":15,"ready":{},"pumped":24,"hoist":false}).is_empty(),"no surface landings before the repair")
	expect(Mines.surface_landings({"unlocked":10,"ready":{},"pumped":24,"hoist":true})==[6,10] and Mines.lift_targets(10)==[6,10],"repaired hoist offers the opened landings")
	expect(World.NAMES.get("ochre_earth")=="赭土" and World.NAMES.get("vein_quartz")=="脈石英","new minerals are registered items")
	expect(World.BUILD.get("glass_furnace",{})=={"name":"玻璃爐","stone":25,"iron_ingot":6},"glass furnace build cost")
	var furnace:=World.processing_recipes("glass_furnace")
	expect(furnace.size()==4 and furnace.has("glass") and furnace.has("crystal_sand") and furnace.has("iron_ingot") and furnace.has("copper_ingot"),"Glass furnace retains glass, sand and legacy smelting recipes")
	expect(furnace.get("glass",{}).get("ingredients",{})=={"crystal_sand":3,"wood":1} and float(furnace.get("glass",{}).get("time",0))==120.0 and int(furnace.get("glass",{}).get("yield",0))==1,"furnace glass: 3 crystal sand + 1 wood -> 1 in 120 s")
	expect(furnace.get("crystal_sand",{}).get("ingredients",{})=={"vein_quartz":2} and float(furnace.get("crystal_sand",{}).get("time",0))==60.0 and int(furnace.get("crystal_sand",{}).get("yield",0))==3,"furnace crystal sand: 2 vein quartz -> 3 in 60 s")
	expect(World.CRAFT.glass.ingredients=={"crystal_sand":2,"charcoal":1} and int(World.CRAFT.glass.yield)==2,"workbench glass recipe unchanged")
	expect(Schema.processing_recipes("glass_furnace").keys().size()==4 and "glass_furnace" in Schema.PROCESSING_STATIONS,"save schema knows the furnace queue")
	expect("glass_furnace" in Sources.STATION_FOR.queue_processing and "glass_furnace" in Sources.STATIONS and "glass_furnace" in Sources.OWNER_ONLY,"material sources: owner-only processing station")
	expect("glass_furnace" in Rooms.SOLID_OBJECTS and "glass_furnace" in World.UNDO_SOLID,"furnace is solid like the loom")
	expect("glass_furnace" not in World.LOGISTICS.PROCESSORS,"furnace is never conveyor-automated")

func check_fresh(w:World)->void:
	expect(w.state.mine_depths.size()==4 and w.state.mine_depths.get("hoist")==false,"fresh world: hoist false")
	expect(valid(w.state.duplicate(true)),"fresh world validates")
	expect(w.region_snapshot(SURFACE).get("mine_depths",{}).get("hoist")==false,"public snapshot carries hoist=false")

func check_quest(w:World,path:String)->void:
	var broken:=path.path_join("missing").path_join("file")
	# PRESET
	w.state.picnic=true
	w.state.mine_depths={"unlocked":5,"ready":{},"pumped":24,"hoist":false}
	w.state.players[OWNER]["inventory"]={"copper_joint":12,"plank":4,"stone":25,"iron_ingot":6,"crystal_sand":3,"wood":1,"vein_quartz":2}
	w.state.players[OTHER]["inventory"]={"copper_joint":12,"plank":4}
	relocate(w,OWNER,SURFACE,SURFACE_ARRIVAL)
	relocate(w,OTHER,SURFACE,SURFACE_ARRIVAL)
	expect(valid(w.state.duplicate(true)),"preset unlocked-5 state validates")

	# Before B6: repair, furnace and surface hoist are all closed.
	refuse(w,OWNER,World.HOIST_ACTION,Mines.ENTRY,"",World.HOIST_LOCKED_MSG,"repair before B6 is open")
	refuse(w,OWNER,"mine_travel",Mines.ENTRY,"mine_6",CLOSED,"surface hoist to B6 while only B5 is open")
	relocate(w,OWNER,"home",World.SPAWN)
	refuse(w,OWNER,"build",TILE,"glass_furnace",World.GLASS_FURNACE_LOCKED_MSG,"glass furnace before the hoist repair")
	relocate(w,OWNER,SURFACE,SURFACE_ARRIVAL)

	# PRESET: B6 opened (the commission itself is covered elsewhere).
	w.state.mine_depths["unlocked"]=6
	refuse(w,OWNER,"mine_travel",Mines.ENTRY,"mine_6",World.HOIST_STUCK_MSG,"surface hoist to B6 is stuck before the repair")
	refuse(w,OWNER,"mine_travel",Mines.ENTRY,"mine_10",CLOSED,"B10 is not open yet (not a stuck-hoist refusal)")
	relocate(w,OWNER,"home",World.SPAWN)
	refuse(w,OWNER,"build",TILE,"glass_furnace",World.GLASS_FURNACE_LOCKED_MSG,"glass furnace with B6 open but the hoist stuck")
	relocate(w,OWNER,SURFACE,SURFACE_ARRIVAL)
	# Walking into B1 stays free; repair is refused away from the surface sign.
	var walk:=act(w,OWNER,"mine_travel",Mines.ENTRY,"mine_1")
	expect(walk.ok and w.player_region(OWNER)=="mine_1","walking into B1 is free before the repair")
	refuse(w,OWNER,World.HOIST_ACTION,Mines.ENTRY,"",WRONG_PLACE,"repair from inside B1 (wrong region)")
	var back:=act(w,OWNER,"mine_travel",Mines.UP,SURFACE)
	expect(back.ok and w.player_region(OWNER)==SURFACE,"B1 stairs back to the surface")
	refuse(w,OWNER,World.HOIST_ACTION,Mines.UP,"",WRONG_PLACE,"repair at the wrong surface cell")
	relocate(w,OWNER,"home",World.SPAWN)
	refuse(w,OWNER,World.HOIST_ACTION,Mines.ENTRY,"",WRONG_PLACE,"repair from home (wrong region)")
	relocate(w,OWNER,SURFACE,SURFACE_ARRIVAL)
	# Lacking materials (one plank short), whole bag unchanged.
	bag(w,OWNER)["plank"]=3
	refuse(w,OWNER,World.HOIST_ACTION,Mines.ENTRY,"",World.HOIST_SHORT_MSG,"repair one plank short")
	bag(w,OWNER)["plank"]=4
	# The B6 cage up to the surface always works, even with the hoist stuck.
	relocate(w,OTHER,"mine_6",Vector2(Mines.LIFT)+Vector2(0.5,1.5))
	var up:=act(w,OTHER,"mine_travel",Mines.LIFT,SURFACE)
	expect(up.ok and w.player_region(OTHER)==SURFACE and Vector2(w.state.players[OTHER].x,w.state.players[OTHER].y).distance_to(SURFACE_ARRIVAL)<=3.2,"B6 cage rides up before the repair")
	# Save failure rolls the repair back.
	place(w,OWNER,Mines.ENTRY)
	var before_broken:=w.state.duplicate(true)
	w.save_path=broken
	expect(not w.act(OWNER,rid("broken-repair"),World.HOIST_ACTION,Mines.ENTRY).ok and w.state==before_broken,"repair save failure rolls back")
	w.save_path=path

	# Successful repair: exact debit, once.
	var bag_before:=canon(bag(w,OWNER))
	var repair:=act(w,OWNER,World.HOIST_ACTION,Mines.ENTRY,"","hoist-repair")
	expect(repair.ok and str(repair.message)==World.HOIST_OK_MSG,"repair succeeds with the reward message (%s)"%str(repair.get("message","")))
	expect(canon(bag(w,OWNER))==adjusted(bag_before,negated(Mines.HOIST_COST)),"repair debits exactly HOIST_COST (bag %s)"%str(canon(bag(w,OWNER))))
	expect(Mines.hoist_ready(w.state.mine_depths) and int(w.state.mine_depths.unlocked)==6,"hoist repaired, depth unchanged")
	var after_repair:=canon(bag(w,OWNER))
	var resent:=act(w,OWNER,World.HOIST_ACTION,Mines.ENTRY,"","hoist-repair")
	expect(resent==repair and canon(bag(w,OWNER))==after_repair,"resending the same request replays the receipt without charging again")
	refuse(w,OWNER,World.HOIST_ACTION,Mines.ENTRY,"",World.HOIST_DONE_MSG,"a fresh second repair request")
	refuse(w,OTHER,World.HOIST_ACTION,Mines.ENTRY,"",World.HOIST_DONE_MSG,"another islander cannot repair it again")
	expect(w.region_snapshot(SURFACE).get("mine_depths",{}).get("hoist")==true and w.region_snapshot("home").get("mine_depths",{}).get("hoist")==true,"public snapshots carry hoist=true")
	# Surface hoist now lowers to B6; the cage still returns.
	var down:=act(w,OWNER,"mine_travel",Mines.ENTRY,"mine_6")
	expect(down.ok and w.player_region(OWNER)=="mine_6" and Vector2(w.state.players[OWNER].x,w.state.players[OWNER].y).distance_to(Vector2(Mines.LIFT)+Vector2(0.5,0.5))<=1.6,"surface hoist lowers to B6 after the repair")
	var lift_back:=act(w,OWNER,"mine_travel",Mines.LIFT,SURFACE)
	expect(lift_back.ok and w.player_region(OWNER)==SURFACE,"B6 cage returns to the surface")

	# Save -> reload in a fresh World keeps the repaired hoist.
	var reload:=World.new()
	expect(reload.load_world(path) and not reload.recovered_from_backup,"repaired save loads in a fresh World")
	expect(reload.state.mine_depths.get("hoist")==true and int(reload.state.mine_depths.unlocked)==6 and int(reload.state.version)==26,"reload keeps hoist=true without a version bump")

	# Glass furnace: unlocked by the repair, exact cost.
	relocate(w,OWNER,"home",World.SPAWN)
	relocate(w,OTHER,"home",World.SPAWN)
	var before_build:=canon(bag(w,OWNER))
	var built:=act(w,OWNER,"build",TILE,"glass_furnace")
	expect(built.ok,"glass furnace builds after the repair (%s)"%str(built.get("message","")))
	expect(canon(bag(w,OWNER))==adjusted(before_build,negated(FURNACE_COST)),"furnace debits exactly %s"%str(FURNACE_COST))
	var furnace:Dictionary=w.state.objects.get(World.key(TILE),{})
	expect(furnace.get("type")=="glass_furnace" and furnace.get("owner")==OWNER and not furnace.has("auto_enabled") and not furnace.has("job") and (furnace.get("items",{}) as Dictionary).is_empty(),"furnace is a plain owner-only manual station")
	for offset:Vector2i in World.INDUSTRY.SQUARE_CELLS:
		expect(w.blocked(TILE+offset) and World.station_anchor(w.state.objects,TILE+offset)==TILE,"Furnace corner blocks and resolves to the same station")
	# Queue: owner only, its own recipes only.
	refuse(w,OTHER,"queue_processing",TILE,"glass","只能使用自己的加工設備","another islander cannot use the furnace")
	refuse(w,OWNER,"queue_processing",TILE,"cotton_cloth","這台設備不能加工此物品","furnace refuses a loom recipe")
	var before_glass:=canon(bag(w,OWNER))
	var glass:=act(w,OWNER,"queue_processing",TILE,"glass")
	expect(glass.ok and canon(bag(w,OWNER))==adjusted(before_glass,{"crystal_sand":-3,"wood":-1}),"glass job debits 3 crystal sand + 1 wood")
	var before_sand:=canon(bag(w,OWNER))
	var sand:=act(w,OWNER,"queue_processing",TILE,"crystal_sand")
	expect(sand.ok and canon(bag(w,OWNER))==adjusted(before_sand,{"vein_quartz":-2}),"crystal sand job debits 2 vein quartz")
	refuse(w,OWNER,"remove",TILE,"",World.PROCESSING_MSG_BUSY,"busy furnace cannot be removed")
	# Reload keeps the queued jobs.
	var w3:=World.new()
	if not expect(w3.load_world(path) and not w3.recovered_from_backup,"furnace queue save loads"):return
	var queued:Dictionary=w3.state.objects.get(World.key(TILE),{})
	var processing=queued.get("processing")
	expect(queued.get("type")=="glass_furnace" and processing is Dictionary and str(processing.get("active",{}).get("kind",""))=="glass" and (processing.get("waiting",[]) as Array).size()==1,"reload keeps the active glass job and the waiting crystal sand job")
	refuse_prefix(w3,OWNER,"claim_processing",TILE,"加工尚未完成","claim before the glass is done")
	expect(w3.step(120.1,true),"120 world seconds pass")
	refuse(w3,OTHER,"claim_processing",TILE,"","只能使用自己的加工設備","another islander cannot claim the glass")
	var before_claim:=canon(bag(w3,OWNER))
	var claimed:=act(w3,OWNER,"claim_processing",TILE)
	expect(claimed.ok and canon(bag(w3,OWNER))==adjusted(before_claim,{"glass":1}),"claim gives exactly 1 glass")
	refuse_prefix(w3,OWNER,"claim_processing",TILE,"加工尚未完成","glass is claimed once; crystal sand is still running")
	expect(w3.step(60.1,true),"60 more world seconds pass")
	var before_sand_claim:=canon(bag(w3,OWNER))
	var sand_claim:=act(w3,OWNER,"claim_processing",TILE)
	expect(sand_claim.ok and canon(bag(w3,OWNER))==adjusted(before_sand_claim,{"crystal_sand":3}),"claim gives exactly 3 crystal sand")
	refuse(w3,OWNER,"claim_processing",TILE,"","目前沒有完成的加工","nothing left to claim")
	# Every preset material was spent exactly: repair + furnace + two jobs.
	expect(canon(bag(w3,OWNER))=={"glass":1,"crystal_sand":3},"owner ends with exactly the furnace products (%s)"%str(canon(bag(w3,OWNER))))
	var final_check:=World.new()
	expect(final_check.load_world(path) and final_check.state.mine_depths.get("hoist")==true,"final save still loads with the repaired hoist")
	# A furnace can only exist after the repair: the same save with the hoist
	# flag cleared is rejected, and accepted again once the furnace is gone.
	expect(valid(final_check.state.duplicate(true)),"control: furnace + repaired hoist validates")
	var stuck:Dictionary=final_check.state.duplicate(true)
	stuck.mine_depths["hoist"]=false
	expect(not valid(stuck.duplicate(true)),"a save holding a glass furnace with the hoist still stuck is rejected")
	for offset:Vector2i in World.INDUSTRY.SQUARE_CELLS:stuck.objects.erase(World.key(TILE+offset))
	expect(valid(stuck),"control: the stuck-hoist save validates once the furnace is removed")
	var design:=World.BLUEPRINT_DESIGN
	var snapshot:={"objects":final_check.state.objects}
	expect(not design.capture(snapshot,OWNER,Rect2i(TILE,Vector2i.ONE),"半座爐",World.BUILD,World.NAMES).ok,"A partial glass furnace cannot be captured")
	var wide:=design.capture(snapshot,OWNER,Rect2i(TILE,Vector2i(2,2)),"玻璃爐",World.BUILD,World.NAMES)
	expect(wide.ok and wide.blueprint.pieces.size()==1 and wide.blueprint.pieces[0].settings.wide,"Wide glass furnace has one canonical blueprint piece")
	if wide.ok:
		var rotated:=design.rotate(wide.blueprint,3,World.BUILD,World.NAMES)
		expect(rotated.ok and rotated.blueprint==wide.blueprint,"Glass furnace retains the footprint on rotation")
	for offset:Vector2i in World.INDUSTRY.SQUARE_CELLS:final_check.state.objects.erase(World.key(TILE+offset))
	final_check.state.objects[World.key(TILE)]={"type":"glass_furnace","owner":OWNER,"items":{}}
	var old_bag:=canon(bag(final_check,OWNER))
	expect(act(final_check,OWNER,"remove",TILE).ok and canon(bag(final_check,OWNER))==adjusted(old_bag,World.LEGACY_GLASS_FURNACE_COST),"Legacy glass furnace still refunds its original recipe")

func write_json(path:String,data:Dictionary)->bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

func legacy_world(unlocked:int)->World:
	var w:=World.new()
	w.add_player(OWNER,"Owner")
	w.state.picnic=true
	# Pre-Q07 shape: exactly three keys, no `hoist`.
	w.state.mine_depths={"unlocked":unlocked,"ready":{},"pumped":24}
	relocate(w,OWNER,SURFACE,SURFACE_ARRIVAL)
	return w

func check_legacy_and_validation()->void:
	for unlocked in [5,9]:
		var path:=temp_path("legacy-%d"%unlocked)
		var source:=legacy_world(unlocked)
		expect(source.state.mine_depths.size()==3 and write_json(path,source.state),"write pre-Q07 save with unlocked %d"%unlocked)
		var loaded:=World.new()
		expect(loaded.load_world(path) and not loaded.recovered_from_backup,"pre-Q07 save with unlocked %d loads"%unlocked)
		var depths:Dictionary=loaded.state.mine_depths
		expect(int(loaded.state.version)==26 and depths.size()==4 and int(depths.unlocked)==unlocked and depths.get("hoist")==(unlocked>=6),"unlocked %d loads as hoist=%s"%[unlocked,str(unlocked>=6)])
	var base:=legacy_world(6)
	base.state.mine_depths["hoist"]=true
	expect(valid(base.state.duplicate(true)),"control: hoist true with unlocked 6 validates")
	var low:=base.state.duplicate(true)
	low.mine_depths={"unlocked":3,"ready":{},"pumped":0,"hoist":true}
	expect(not valid(low),"hoist true with unlocked 3 is rejected")
	var low_ok:=base.state.duplicate(true)
	low_ok.mine_depths={"unlocked":3,"ready":{},"pumped":0,"hoist":false}
	expect(valid(low_ok),"control: hoist false with unlocked 3 validates")
	var text:=base.state.duplicate(true)
	text.mine_depths={"unlocked":6,"ready":{},"pumped":24,"hoist":"yes"}
	expect(not valid(text),"non-bool hoist is rejected")
	var extra:=base.state.duplicate(true)
	extra.mine_depths={"unlocked":6,"ready":{},"pumped":24,"hoist":true,"lift":true}
	expect(not valid(extra),"unknown extra mine_depths key is rejected")

func check_mining()->void:
	var w:=World.new()
	w.add_player(OWNER,"Owner")
	w.state.picnic=true
	w.state.mine_depths={"unlocked":9,"ready":{},"pumped":24,"hoist":false}
	w.state.players[OWNER]["inventory"]={"reinforced_pick":1}
	for depth in [6,9]:
		relocate(w,OWNER,"mine_%d"%depth,Vector2(Mines.REST)+Vector2(0.5,0.5))
		var new_find:="ochre_earth" if depth==6 else "vein_quartz"
		expect(new_find in Mines.finds(depth),"B%d finds include %s"%[depth,new_find])
		var expected:={Mines.ORES[depth-1]:int(Mines.YIELDS[depth-1])}
		for found in Mines.finds(depth):expected[found]=int(expected.get(found,0))+1
		for node in [Mines.NODES[0],Mines.NODES[1]]:
			var before:=canon(bag(w,OWNER))
			var strike:=act(w,OWNER,"mine_extract",node)
			expect(strike.ok and canon(bag(w,OWNER))==adjusted(before,expected),"B%d strike at %s gives %s (got %s)"%[depth,str(node),str(expected),str(canon(bag(w,OWNER)))])
			expect(int(canon(bag(w,OWNER)).get(new_find,0))-int(before.get(new_find,0))==1,"B%d strike gives %s +1"%[depth,new_find])
