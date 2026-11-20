extends SceneTree
## C11 石工台 focused regression. Pure World (no scene, no UI); works with --headless.
## Not run by the author (no Godot in the authoring session): Codex runs it.
##
## Contract pinned here:
##   - id `stone_workbench`, 20 stone + 8 wood, 2x1 solid piece (1x2 when a blueprint rotates it), every cell
##     carries `stone_bench_part` (0 anchor, 1 far end) [+ `stone_bench_vertical`]. Zero mining prerequisites.
##   - Locked until Q03 (`state.board`, written only by the real donate / public fund actions); unlocked after;
##     the unlock survives a real save -> load_world round trip.
##   - Either end crafts; the far end is never a second station or a second refund.
##   - Recipe `bridge_foundation` (stone only) is the Q05 河灣橋 component: a world finishing Q03 now owes
##     FOUNDATIONS_NEEDED of them; legacy worlds without `bridge_project` keep an open bridge.
##   - New stone floors (R11) and small smelters (R12) need the station; existing pieces, undo and load do not.

const World=preload("res://scripts/world.gd")
const I=World.INDUSTRY
const S=World.STONE_WORKSHOP
const Design=World.BLUEPRINT_DESIGN
const KIND:="stone_workbench"
const FIELD:="stone_bench_part"
const VFIELD:="stone_bench_vertical"
const BOARD:=Vector2i(40,29)
## Test yard (cleared in run): x 38..50, y 33..40. (45,34) and the 38..44 x 28..31 block are protected.
const HOME:=Vector2i(40,35)
const DEST:=Vector2i(44,35)
const TALL:=Vector2i(47,35)
const SMELT:=Vector2i(47,37)
const FLOOR:=Vector2i(42,38)
const BRIDGE_TILE:=Vector2i(55,30)

var world:World
var owner:="stone-owner"
var guest:="stone-guest"
var path:String
var checks:=0
var failures:=0
var serial:=0
var nonce:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func act(verb:String,tile:Vector2i,extra:="",who:="")->Dictionary:
	serial+=1
	return world.act(owner if who.is_empty() else who,"stone-workbench-%d"%serial,verb,tile,extra)

func next_nonce()->String:
	nonce+=1
	return ("%02x"%nonce).repeat(16)

# ---------------------------------------------------------------- helpers --

func valid(state:Dictionary)->bool:
	return bool(World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME))

func bag(item:String)->int:
	return int(world.state.players[owner].inventory.get(item,0))

func put(token:String,at:Vector2)->void:
	world.state.players[token].x=at.x
	world.state.players[token].y=at.y

func centre(tile:Vector2i)->Vector2:
	return Vector2(tile)+Vector2(0.5,0.5)

func cells_of(anchor:Vector2i,vertical:bool)->Array[Vector2i]:
	var out:Array[Vector2i]=[]
	for offset:Vector2i in I.station_cells(KIND,vertical):out.append(anchor+offset)
	return out

func parts_ok_in(w:World,anchor:Vector2i,vertical:bool)->bool:
	var list:=cells_of(anchor,vertical)
	for index in list.size():
		var piece:Dictionary=w.state.objects.get(World.key(list[index]),{})
		if piece.get("type")!=KIND or piece.get("owner")!=owner or int(piece.get(FIELD,-1))!=index or I.is_vertical(piece)!=vertical:return false
	return true

func parts_ok(anchor:Vector2i,vertical:bool)->bool:
	return parts_ok_in(world,anchor,vertical)

func all_blocked(list:Array[Vector2i],expected:bool)->bool:
	for tile:Vector2i in list:
		if world.blocked(tile)!=expected or world.can_stand(centre(tile))==expected:return false
	return true

func empty(list:Array[Vector2i])->bool:
	for tile:Vector2i in list:
		if world.state.objects.has(World.key(tile)):return false
	return true

func obj(tile:Vector2i)->Dictionary:
	return world.state.objects.get(World.key(tile),{})

func put_chest(tile:Vector2i,items:Dictionary)->void:
	world.state.objects[World.key(tile)]={"type":"chest","owner":owner,"items":items.duplicate()}

func project()->Dictionary:
	return world.state.get(S.PROJECT_KEY,{})

func bridge_walkable()->bool:
	return not world.water(BRIDGE_TILE) and world.can_stand(centre(BRIDGE_TILE))

## Resets the yard, the owner's bag, position and the whole Q03/Q05 progression (a brand new island).
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
	var person:Dictionary=world.state.players[owner]
	person.inventory={"wood":100,"stone":100,"copper_ore":10}
	person.crafting_points=0
	person.erase("resident_participation")
	person.builds=0
	put(owner,Vector2(41.0,36.7))
	put(guest,Vector2(49.5,39.5))

## The real Q03 route: donate 30 wood + 10 stone at the board. Leaves bag and position as they were.
func q03()->Dictionary:
	var bag_before:Dictionary=world.state.players[owner].inventory.duplicate()
	var at:=Vector2(world.state.players[owner].x,world.state.players[owner].y)
	world.state.players[owner].inventory={"wood":30,"stone":10}
	put(owner,centre(BOARD)+Vector2(0.0,1.0))
	var result:=act("donate",BOARD)
	world.state.players[owner].inventory=bag_before
	put(owner,at)
	return result

## Q05 wood + rope through the real board action `bridge_donate`. Leaves the bag and position as they were.
func q05_donate(who:="",wood:=60,rope:=4)->Dictionary:
	var token:=owner if who.is_empty() else who
	var person:Dictionary=world.state.players[token]
	var bag_before:Dictionary=person.inventory.duplicate()
	var at:=Vector2(person.x,person.y)
	person.inventory={"wood":wood,"rope":rope}
	put(token,centre(BOARD)+Vector2(0.0,1.0))
	var result:=act(S.DONATE_ACTION,BOARD,"",token)
	person.inventory=bag_before
	put(token,at)
	return result

## Q03 done and the bridge project pending (the new-game state).
func unlocked()->void:
	fresh()
	var done:=q03()
	expect(done.ok and world.state.board==true,"fixture: Q03 completes through the real donate action: "+str(done.get("message","")))

func snapshot_of(tiles:Array[Vector2i])->Array:
	var out:Array=[]
	for tile:Vector2i in tiles:out.append(obj(tile).duplicate(true))
	return out

func finish()->void:
	for suffix in ["",".bak",".tmp",".staged",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	if FileAccess.file_exists(path+".corrupt"):DirAccess.remove_absolute(path+".corrupt")
	print("STONE_WORKBENCH_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

# -------------------------------------------------------------- scenarios --

func contract_scenario()->void:
	var recipe:Dictionary=World.BUILD[KIND]
	expect(I.STONE_WORKBENCH==KIND and World.BUILD.has(KIND),"stable id stone_workbench is registered")
	expect(recipe.name=="石工台" and int(recipe.stone)==20 and int(recipe.wood)==8 and recipe.size()==3,"the recipe is 20 stone + 8 wood and nothing from the mine")
	expect(KIND in World.UNDO_SOLID,"the station is a solid kind")
	expect(KIND in I.TWO_CELL_STATIONS and KIND in I.ORIENTABLE_FOOTPRINTS,"it uses the normal two-cell footprint family")
	expect(I.station_cells(KIND,false)==[Vector2i.ZERO,Vector2i.RIGHT] and I.station_cells(KIND,true)==[Vector2i.ZERO,Vector2i.DOWN],"footprint is 2x1 / 1x2")
	expect(I.square_part_field(KIND)==FIELD and I.vertical_field(KIND)==VFIELD,"part and orientation fields")
	expect(S.FOUNDATION_COST=={"stone":10} and S.FOUNDATIONS_NEEDED==2,"chosen tuning: 2 foundations of 10 stone (20 stone, the spec's Q05 stone figure)")
	expect(S.FOUNDATION_COST.size()==1 and S.FOUNDATION_COST.has("stone"),"the foundation costs stone only")
	expect(S.STATION_BUILDS==["stone_floor","small_smelter"] and World.BUILD.has("stone_floor") and World.BUILD.has("small_smelter"),"R11/R12 are the kinds routed through the station")
	expect(int(World.BUILD.stone_floor.stone)==2 and int(World.BUILD.small_smelter.stone)==25 and int(World.BUILD.small_smelter.copper_ore)==5,"R11 costs 2 stone, R12 25 stone + 5 copper ore")
	var ids:=[]
	for entry:Dictionary in S.RECIPES:ids.append(entry.id)
	expect(ids.has("stone_floor") and ids.has("small_smelter") and ids.has(S.FOUNDATION) and ids.has("spring_stone_bench") and ids.has("inn_stone_footbath"),"the recipe card lists R11, R12, the foundation and the established stone furniture")
	expect(S.bridge_open({"board":true}) and not S.bridge_open({"board":false}) and not S.bridge_open({"board":true,S.PROJECT_KEY:S.fresh_project()}),"bridge_open: legacy open, unfinished project closed, no board closed")

func progression_scenario()->void:
	# Locked on a brand new island: nothing is spent, nothing is placed.
	fresh()
	var wood:=bag("wood")
	var stone:=bag("stone")
	var builds:=int(world.state.players[owner].builds)
	var denied:=act("build",HOME,KIND)
	expect(not denied.ok and denied.message==S.LOCKED_MSG,"locked before Q03: "+str(denied.get("message","")))
	expect(empty(cells_of(HOME,false)) and bag("wood")==wood and bag("stone")==stone and int(world.state.players[owner].builds)==builds,"a refused build changes nothing")
	# A UI-only flag cannot unlock anything: the client never writes state.board, only donate does.
	expect(not world.state.board and not world.state.has(S.PROJECT_KEY),"the new island has no bridge project yet")
	# A partial donation keeps its contributions and does not unlock.
	world.state.players[owner].inventory={"wood":12,"stone":3}
	put(owner,centre(BOARD)+Vector2(0.0,1.0))
	expect(act("donate",BOARD).ok and not world.state.board and world.state.donations=={"wood":12,"stone":3},"a partial donation is recorded and stays recorded")
	world.state.players[owner].inventory={"wood":100,"stone":100}
	put(owner,Vector2(41.0,36.7))
	expect(not act("build",HOME,KIND).ok,"still locked with a partial donation")
	# Finish Q03 through the real action.
	world.state.players[owner].inventory={"wood":50,"stone":50}
	put(owner,centre(BOARD)+Vector2(0.0,1.0))
	var donated:=act("donate",BOARD)
	expect(donated.ok and world.state.board==true and world.state.donations=={"wood":30,"stone":10},"the donation completes Q03 and keeps its totals: "+str(donated.get("message","")))
	expect(str(donated.message).contains("石工台做橋基") and str(donated.message).contains("木材和繩索修河灣橋"),"the message points the player at the required bridge work")
	expect(project()=={"foundations":0,"done":false} and not bridge_walkable(),"Q05 now waits for foundations: the river is still closed")
	expect(valid(world.state.duplicate(true)),"the pending project validates")
	# Unlocked after Q03: zero mining needed (no copper, iron or depth in the bag or the world).
	world.state.players[owner].inventory={"wood":100,"stone":100}
	put(owner,Vector2(41.0,36.7))
	expect(int(world.state.mine_depths.unlocked)<=1,"fixture: no mine progress")
	var built:=act("build",HOME,KIND)
	expect(built.ok and parts_ok(HOME,false),"unlocked after Q03: "+str(built.get("message","")))
	expect(bag("stone")==80 and bag("wood")==92,"it cost exactly 20 stone + 8 wood")
	# The second donation attempt is refused and says where the bridge work is.
	var again:=act("donate",BOARD)
	expect(not again.ok,"the finished board takes no more donations")
	# Public fund route (the other way to finish Q03) opens the same project.
	fresh()
	world.state.public_fund={"balance":1000000,"contributors":{}}
	put(owner,centre(BOARD)+Vector2(0.0,1.0))
	var funded:=act("fund_bridge",BOARD)
	expect(funded.ok and world.state.board and project()=={"foundations":0,"done":false} and not bridge_walkable(),"the public fund finishes Q03 and leaves Q05 pending")
	put(owner,Vector2(41.0,36.7))
	expect(act("build",HOME,KIND).ok,"the fund route unlocks the station too")

func direct_build_scenario()->void:
	unlocked()
	var wood:=bag("wood")
	var stone:=bag("stone")
	var builds:=int(world.state.players[owner].builds)
	var built:=act("build",HOME,KIND)
	var both:=cells_of(HOME,false)
	expect(built.ok,"direct build places the station: "+str(built.get("message","")))
	expect(bag("wood")==wood-8 and bag("stone")==stone-20,"one charge for both cells")
	expect(int(world.state.players[owner].builds)==builds+1,"one build is counted, not two")
	expect(parts_ok(HOME,false),"both cells are one station with matching parts")
	expect(all_blocked(both,true),"both cells block walking")
	expect(World.station_anchor(world.state.objects,HOME+Vector2i.RIGHT)==HOME and World.station_anchor(world.state.objects,HOME)==HOME,"the far end resolves to the anchor")
	expect(valid(world.state.duplicate(true)),"the station validates")
	var tall:=world._build_piece(owner,TALL,KIND,true,false,true,true)
	expect(tall.ok and parts_ok(TALL,true) and all_blocked(cells_of(TALL,true),true),"a vertical station covers both rows and blocks both")
	expect(obj(TALL).get(VFIELD)==true and obj(TALL+Vector2i.DOWN).get(VFIELD)==true,"both vertical cells carry the orientation")
	expect(valid(world.state.duplicate(true)),"a vertical station validates")
	# Atomic refusals.
	var far:=HOME+Vector2i.RIGHT
	unlocked()
	wood=bag("wood")
	stone=bag("stone")
	var untouched:=func()->bool:return empty(cells_of(HOME,false)) and bag("wood")==wood and bag("stone")==stone
	put_chest(far,{})
	var crowded_far:=act("build",HOME,KIND)
	expect(not crowded_far.ok and obj(far).get("type")=="chest" and not world.state.objects.has(World.key(HOME)) and bag("wood")==wood and bag("stone")==stone,"an object on the far cell refuses the build and survives")
	world.state.objects.erase(World.key(far))
	put(guest,centre(far))
	expect(not act("build",HOME,KIND).ok and untouched.call(),"a player standing on the far cell refuses the build")
	put(guest,Vector2(49.5,39.5))
	expect(act("build",HOME,KIND).ok and parts_ok(HOME,false),"control: the same spot builds once the far cell is clear")

func interaction_scenario()->void:
	var far:=HOME+Vector2i.RIGHT
	unlocked()
	expect(not act(S.ACTION,HOME,S.FOUNDATION).ok,"no station, no crafting")
	act("build",HOME,KIND)
	world.state.players[owner].inventory={"stone":40,"wood":0}
	var points:=int(world.state.players[owner].get("crafting_points",0))
	# 3.1 tiles from the far end and 4.1 from the anchor: only a two-cell station's either-end reach allows this.
	put(owner,Vector2(44.6,35.5))
	var from_far:=act(S.ACTION,far,S.FOUNDATION)
	expect(from_far.ok and int(project().foundations)==1 and bag("stone")==30,"crafting from the far end works and spends 10 stone: "+str(from_far.get("message","")))
	expect(int(world.state.players[owner].crafting_points)==points+1,"one craft earns one crafting point")
	expect(world.state.players[owner].resident_participation.get("bridge")==true,"the contribution is recorded as bridge participation")
	put(owner,Vector2(44.9,35.5))
	var stone:=bag("stone")
	expect(not act(S.ACTION,far,S.FOUNDATION).ok and not act(S.ACTION,HOME,S.FOUNDATION).ok and int(project().foundations)==1 and bag("stone")==stone,"beyond reach of both ends nothing is crafted")
	put(owner,Vector2(41.0,36.7))
	expect(not act(S.ACTION,far,"missing-recipe").ok and not act(S.ACTION,far,"stone_floor").ok and bag("stone")==stone,"unknown recipes and build routes are not crafts")
	world.state.players[owner].inventory={"stone":9}
	expect(not act(S.ACTION,HOME,S.FOUNDATION).ok and int(project().foundations)==1 and bag("stone")==9,"9 stone is not enough")
	world.state.players[owner].inventory={"stone":40}
	# Q05 also owes wood and rope: two foundations alone do not open the river.
	var wood_rope:=q05_donate()
	expect(wood_rope.ok and project().wood==60 and project().rope==4 and project().done==false and not bridge_walkable(),"wood and rope are donated through the board; the bridge still waits for the second foundation")
	# A friend contributes from the shared station: progress is island-wide.
	put(guest,Vector2(42.9,36.2))
	world.state.players[guest].inventory={"stone":10}
	var friend:=act(S.ACTION,HOME,S.FOUNDATION,guest)
	expect(friend.ok and int(project().foundations)==2 and project().done==true,"a friend completes the second foundation: "+str(friend.get("message","")))
	expect(bridge_walkable(),"the river crossing opens exactly when the foundations are complete")
	expect(str(friend.message).contains("河灣橋開通") and world.state.events.any(func(line):return str(line).contains("橋基")),"completion is announced")
	put(owner,Vector2(41.0,36.7))
	var spent:=bag("stone")
	expect(not act(S.ACTION,HOME,S.FOUNDATION).ok and bag("stone")==spent and int(project().foundations)==2,"no third foundation and no charge once the bridge is done")
	expect(valid(world.state.duplicate(true)),"the finished project validates")
	# The old bench is not a stone workbench, and a stone workbench is not a bench.
	unlocked()
	world.state.objects[World.key(Vector2i(46,34))]={"type":"bench","owner":owner,"items":{}}
	put(owner,Vector2(46.5,35.6))
	expect(not act(S.ACTION,Vector2i(46,34),S.FOUNDATION).ok and not project().is_empty() and int(project().foundations)==0,"a wood bench cannot craft stone recipes")
	put(owner,Vector2(41.0,36.7))
	expect(act("build",HOME,KIND).ok,"fixture: station for the wrong-station checks")
	world.state.players[owner].inventory={"wood":40,"stone":40}
	expect(not act("craft",HOME,"sawmill_kit").ok and bag("wood")==40,"a stone workbench cannot craft wood recipes")
	# Locked station (board lost in a hand-edited save) refuses to craft but still stands.
	world.state.board=false
	expect(not act(S.ACTION,HOME,S.FOUNDATION).ok and obj(HOME).get("type")==KIND,"before Q03 the recipe is refused")

func q05_scenario()->void:
	# Legacy world: board already true, no bridge_project -> the bridge stays open, nothing to craft.
	fresh()
	world.state.board=true
	world.state.donations={"wood":30,"stone":10}
	expect(bridge_walkable() and valid(world.state.duplicate(true)),"a legacy completed project keeps an open bridge")
	world.state.objects[World.key(HOME)]={"type":KIND,"owner":owner,"items":{},FIELD:0}
	world.state.objects[World.key(HOME+Vector2i.RIGHT)]={"type":KIND,"owner":owner,"items":{},FIELD:1}
	put(owner,Vector2(41.0,36.7))
	var stone:=bag("stone")
	expect(not act(S.ACTION,HOME,S.FOUNDATION).ok and bag("stone")==stone and not world.state.has(S.PROJECT_KEY),"a legacy world has no foundation to craft and nothing is charged")
	expect(world.save(),"the legacy world saves")
	var legacy:=World.new()
	expect(legacy.load_world(path) and legacy.state.board==true and not legacy.state.has(S.PROJECT_KEY) and not legacy.water(BRIDGE_TILE),"actual reload: the legacy bridge is still open and no project appears")
	# Modern world: pending project survives a real reload; so do the unlocked station and its progress.
	unlocked()
	act("build",HOME,KIND)
	world.state.players[owner].inventory={"stone":40}
	expect(act(S.ACTION,HOME,S.FOUNDATION).ok and int(project().foundations)==1,"one foundation crafted")
	expect(q05_donate(owner,25,3).ok,"a partial wood and rope donation")
	expect(world.save(),"the modern world saves")
	var modern:=World.new()
	expect(modern.load_world(path) and not modern.recovered_from_backup,"the modern world reloads from its primary save")
	var reloaded_project:Dictionary=modern.state.get(S.PROJECT_KEY,{})
	expect(modern.state.board==true and int(reloaded_project.get("foundations",-1))==1 and reloaded_project.get("done")==false,"actual reload keeps Q03 and the pending project")
	expect(int(modern.state.donations.wood)==30 and int(modern.state.donations.stone)==10,"actual reload keeps the contributions already made")
	expect(modern.water(BRIDGE_TILE) and parts_ok_in(modern,HOME,false),"after reload the bridge is still closed and the station intact")
	# The reloaded world takes the last foundation and opens the bridge for good.
	expect(int(reloaded_project.get("wood",-1))==25 and int(reloaded_project.get("rope",-1))==3,"actual reload keeps the partial wood and rope")
	modern.save_path=path
	modern.state.players[owner].inventory={"wood":100,"rope":9}
	modern.state.players[owner].x=centre(BOARD).x
	modern.state.players[owner].y=centre(BOARD).y+1.0
	var topped:=modern.act(owner,"stone-reload-topup","bridge_donate",BOARD,"")
	expect(topped.ok and modern.state.bridge_project.wood==60 and modern.state.bridge_project.rope==4 and not modern.state.bridge_project.done and int(modern.state.players[owner].inventory.wood)==65 and int(modern.state.players[owner].inventory.rope)==8,"the reloaded world takes exactly the missing 35 wood and 1 rope")
	modern.state.players[owner].inventory={"stone":10}
	modern.state.players[owner].x=41.0
	modern.state.players[owner].y=36.7
	var last:=modern.act(owner,"stone-reload-last","stone_craft",HOME,S.FOUNDATION)
	expect(last.ok and modern.state.bridge_project.done==true and not modern.water(BRIDGE_TILE),"the reloaded world finishes Q05: "+str(last.get("message","")))
	expect(modern.save(),"the finished world saves")
	var done:=World.new()
	var finished_project:Dictionary={}
	if done.load_world(path):finished_project=done.state.get(S.PROJECT_KEY,{})
	expect(int(finished_project.get("foundations",-1))==2 and finished_project.get("done")==true and not done.water(BRIDGE_TILE),"actual reload keeps the bridge open")
	# Validator.
	var good:=world.state.duplicate(true)
	var cases:={}
	var many:=good.duplicate(true);many[S.PROJECT_KEY]={"foundations":3,"done":true};cases["too many foundations"]=many
	var early:=good.duplicate(true);early[S.PROJECT_KEY]={"foundations":1,"done":true};cases["done before the foundations"]=early
	var late:=good.duplicate(true);late[S.PROJECT_KEY]={"foundations":2,"done":false};cases["complete but not done"]=late
	var extra:=good.duplicate(true);extra[S.PROJECT_KEY]={"foundations":1,"done":false,"note":1};cases["unknown field"]=extra
	var text:=good.duplicate(true);text[S.PROJECT_KEY]={"foundations":"1","done":false};cases["foundations as text"]=text
	var flag:=good.duplicate(true);flag[S.PROJECT_KEY]={"foundations":1,"done":"no"};cases["done as text"]=flag
	var neg:=good.duplicate(true);neg[S.PROJECT_KEY]={"foundations":-1,"done":false};cases["negative"]=neg
	var no_board:=good.duplicate(true);no_board.board=false;cases["a project without the board"]=no_board
	var wrong:=good.duplicate(true);wrong[S.PROJECT_KEY]=[1,2];cases["project is not a dictionary"]=wrong
	for label:String in cases:expect(not valid(cases[label]),"the validator rejects: "+label)
	expect(valid(good),"the unmodified fixture validates")

func stone_routes_scenario()->void:
	# Before the station: R11/R12 refused atomically; the station itself comes first.
	unlocked()
	var floor_bag:=bag("stone")
	var refused_floor:=act("build",FLOOR,"stone_floor")
	expect(not refused_floor.ok and refused_floor.message==S.STATION_MSG and not world.state.ground.has(World.key(FLOOR)) and bag("stone")==floor_bag,"R11 needs the station: "+str(refused_floor.get("message","")))
	var area:=act("build_area",FLOOR,"stone_floor|%d|%d"%[FLOOR.x+1,FLOOR.y])
	expect(not area.ok and not world.state.ground.has(World.key(FLOOR)) and bag("stone")==floor_bag,"an area of stone floor is refused as a whole")
	expect(act("build",FLOOR,"floor").ok,"plain wood floors never needed the station")
	world.state.ground.erase(World.key(FLOOR))
	put(owner,centre(SMELT)+Vector2(0.0,2.0))
	var refused_smelter:=act("build",SMELT,"small_smelter")
	expect(not refused_smelter.ok and refused_smelter.message==S.STATION_MSG and not world.state.objects.has(World.key(SMELT)) and bag("stone")==floor_bag and bag("copper_ore")==10,"R12 needs the station: "+str(refused_smelter.get("message","")))
	put(owner,Vector2(41.0,36.7))
	expect(act("build",HOME,KIND).ok,"build the station")
	# With the station both routes work with their exact normal prices.
	var before_stone:=bag("stone")
	var laid:=act("build",FLOOR,"stone_floor")
	expect(laid.ok and str(world.state.ground.get(World.key(FLOOR),{}).get("type",""))=="stone_floor" and bag("stone")==before_stone-2,"R11 costs 2 stone once the station exists: "+str(laid.get("message","")))
	put(owner,centre(SMELT)+Vector2(0.0,2.0))
	before_stone=bag("stone")
	var smelter:=act("build",SMELT,"small_smelter")
	expect(smelter.ok and bag("stone")==before_stone-25 and bag("copper_ore")==5,"R12 costs 25 stone + 5 copper ore: "+str(smelter.get("message","")))
	expect(all_smelter_cells(),"the smelter keeps its 2x2 footprint")
	# A friend's own build also passes: the station is shared, the objects stay private.
	var guest_floor:=Vector2i(43,38)
	put(guest,centre(guest_floor)+Vector2(0.0,1.0))
	world.state.players[guest].inventory={"stone":10}
	var friend_floor:=act("build",guest_floor,"stone_floor",guest)
	expect(friend_floor.ok and world.state.ground[World.key(guest_floor)].owner==guest,"a friend builds a stone floor beside the shared station and owns it")
	put(guest,Vector2(42.9,36.2))
	expect(not act("remove",HOME,"",guest).ok and parts_ok(HOME,false),"a friend standing beside it cannot dismantle the station: ownership stays private")
	# Blueprints follow the same flow (planned new construction).
	var plan:=Design.capture(world.state,owner,Rect2i(FLOOR,Vector2i(1,1)),"石地板",World.BUILD,World.NAMES)
	expect(plan.ok,"capture a stone floor piece: "+str(plan.get("message","")))
	world.state.objects.erase(World.key(HOME))
	world.state.objects.erase(World.key(HOME+Vector2i.RIGHT))
	put(owner,Vector2(44.6,36.7))
	if plan.ok:
		var target:=Vector2i(45,36)
		var no_station:=world.quote_blueprint(owner,plan.blueprint,target,0)
		expect(not no_station.ok,"a blueprint of stone floor is refused without a station")
		world.state.objects[World.key(HOME)]={"type":KIND,"owner":owner,"items":{},FIELD:0}
		world.state.objects[World.key(HOME+Vector2i.RIGHT)]={"type":KIND,"owner":owner,"items":{},FIELD:1}
		var with_station:=world.quote_blueprint(owner,plan.blueprint,target,0)
		expect(with_station.ok and int(with_station.cost.stone)==2,"the same blueprint quotes 2 stone with a station: "+str(with_station.get("message","")))

func all_smelter_cells()->bool:
	for offset:Vector2i in I.SMELTER_CELLS:
		var piece:=obj(SMELT+offset)
		if piece.get("type")!="small_smelter" or not world.blocked(SMELT+offset):return false
	return true

func existing_pieces_scenario()->void:
	# Worlds saved before C11 hold stone floors and smelters with no station anywhere. They keep working.
	fresh()
	world.state.board=true
	world.state.donations={"wood":30,"stone":10}
	world.state.ground[World.key(FLOOR)]={"type":"stone_floor","owner":owner,"items":{}}
	for index in 4:
		var part:Dictionary={"type":"small_smelter","owner":owner,"items":{}}
		if index>0:part.smelter_part=index
		world.state.objects[World.key(SMELT+I.SMELTER_CELLS[index])]=part
	expect(valid(world.state.duplicate(true)),"a pre-C11 world validates without a station")
	# Reloading the world keeps everything (and never demands a station).
	expect(world.save(),"the legacy world saves")
	var reloaded:=World.new()
	expect(reloaded.load_world(path) and all_smelter_in(reloaded) and reloaded.state.ground.has(World.key(FLOOR)),"actual reload: a legacy smelter and stone floor survive with no station")
	# Dismantling an existing smelter needs no station and refunds exactly once.
	var stone:=bag("stone")
	put(owner,centre(SMELT)+Vector2(0.0,2.0))
	var removed:=act("remove",SMELT)
	expect(removed.ok and bag("stone")==stone+25 and bag("copper_ore")==15,"an existing smelter dismantles with one refund and needs no station")
	expect(not act("remove",SMELT).ok and bag("stone")==stone+25,"no second refund")
	var summary:=world.undo_summary(owner)
	if bool(summary.get("available",false)):
		var restored:=act(World.UNDO_ACTION,SMELT,str(summary.get("id","")))
		expect(restored.ok and all_smelter_cells() and bag("stone")==stone and bag("copper_ore")==10,"undo restores the smelter although no station exists")
	# A brand new piece is still refused on that very world: no compatibility bypass.
	put(owner,Vector2(41.0,36.7))
	world.state.ground.erase(World.key(FLOOR))
	var refused:=act("build",FLOOR,"stone_floor")
	expect(not refused.ok and refused.message==S.STATION_MSG,"new construction still needs the station on a legacy world")
	# Earned pieces: build with a station, take the station away, then dismantle and undo -> restore is never blocked.
	unlocked()
	expect(act("build",HOME,KIND).ok and act("build",FLOOR,"stone_floor").ok,"fixture: station and one stone floor built through the real actions")
	world.state.objects.erase(World.key(HOME))
	world.state.objects.erase(World.key(HOME+Vector2i.RIGHT))
	var floor_removed:=act("remove",FLOOR)
	expect(floor_removed.ok and not world.state.ground.has(World.key(FLOOR)),"a stone floor dismantles after its station is gone")
	var floor_undo:=world.undo_summary(owner)
	expect(bool(floor_undo.get("available",false)),"that dismantle is undoable")
	if bool(floor_undo.get("available",false)):
		expect(act(World.UNDO_ACTION,FLOOR,str(floor_undo.get("id",""))).ok and world.state.ground.has(World.key(FLOOR)),"undo restores the stone floor with no station on the island")

func all_smelter_in(w:World)->bool:
	for offset:Vector2i in I.SMELTER_CELLS:
		if w.state.objects.get(World.key(SMELT+offset),{}).get("type")!="small_smelter":return false
	return true

func blueprint_scenario()->void:
	var far:=HOME+Vector2i.RIGHT
	unlocked()
	act("build",HOME,KIND)
	var wide:=Design.capture(world.state,owner,Rect2i(HOME,Vector2i(2,1)),"石工台",World.BUILD,World.NAMES)
	expect(wide.ok and wide.blueprint.pieces==[{"kind":KIND,"x":0,"y":0}],"capturing the station records one piece")
	expect(not Design.capture(world.state,owner,Rect2i(HOME,Vector2i(1,1)),"半個",World.BUILD,World.NAMES).ok,"a capture area cutting the station in half is refused")
	expect(not Design.capture(world.state,owner,Rect2i(far,Vector2i(1,1)),"另半個",World.BUILD,World.NAMES).ok,"a capture area holding only the far end is refused")
	world._build_piece(owner,TALL,KIND,true,false,true,true)
	var tall:=Design.capture(world.state,owner,Rect2i(TALL,Vector2i(1,2)),"石工台直",World.BUILD,World.NAMES)
	expect(tall.ok and tall.blueprint.pieces==[{"kind":KIND,"x":0,"y":0,"settings":{"vertical":true}}],"a vertical station records the vertical setting")
	if not wide.ok or not tall.ok:return
	var turned:=Design.rotate(wide.blueprint,1,World.BUILD,World.NAMES)
	expect(turned.ok and turned.blueprint.pieces==[{"kind":KIND,"x":0,"y":0,"settings":{"vertical":true}}],"rotating the station makes it vertical")
	var back:=Design.rotate(tall.blueprint,3,World.BUILD,World.NAMES)
	expect(back.ok and back.blueprint.pieces==[{"kind":KIND,"x":0,"y":0}],"rotating it back gives the horizontal piece")
	# Quote + apply on an unlocked island.
	unlocked()
	put(owner,Vector2(44.6,36.7))
	var wood:=bag("wood")
	var stone:=bag("stone")
	var quote:=world.quote_blueprint(owner,wide.blueprint,DEST,0)
	expect(quote.ok and int(quote.cost.stone)==20 and int(quote.cost.wood)==8,"quote prices one station once: "+str(quote.get("message","")))
	var laid:=world.apply_blueprint(owner,next_nonce(),wide.blueprint,DEST,0,str(quote.get("hash","")))
	expect(laid.ok and parts_ok(DEST,false) and all_blocked(cells_of(DEST,false),true),"apply builds both cells, solid")
	expect(bag("wood")==wood-8 and bag("stone")==stone-20,"apply charges once")
	var apply_undo:=world.undo_summary(owner)
	if bool(apply_undo.get("available",false)):
		expect(act(World.UNDO_ACTION,DEST,str(apply_undo.get("id",""))).ok and empty(cells_of(DEST,false)) and bag("wood")==wood and bag("stone")==stone,"undoing the apply removes both cells and refunds exactly")
	else:expect(false,"the blueprint apply is undoable")
	# Rotated placement.
	unlocked()
	put(owner,Vector2(42.6,36.8))
	var spin:=world.quote_blueprint(owner,wide.blueprint,HOME,1)
	expect(spin.ok,"a quarter turn quotes a vertical station: "+str(spin.get("message","")))
	if spin.ok:
		var turned_laid:=world.apply_blueprint(owner,next_nonce(),wide.blueprint,HOME,1,str(spin.hash))
		var anchor:=Vector2i(-1000,-1000)
		for k:String in world.state.objects:
			var piece:Dictionary=world.state.objects[k]
			if piece.get("type")==KIND and I.square_part(piece)==0:anchor=World.cell(k)
		expect(turned_laid.ok and anchor.x>-1000 and parts_ok(anchor,true) and all_blocked(cells_of(anchor,true),true),"a turned plan builds the vertical station")
	# Clipped site: far cell occupied -> refused whole, nothing charged.
	unlocked()
	put_chest(DEST+Vector2i.RIGHT,{})
	put(owner,Vector2(44.6,36.7))
	var charged:=bag("stone")
	expect(not world.quote_blueprint(owner,wide.blueprint,DEST,0).ok and bag("stone")==charged,"a plan whose far cell is taken is refused whole")
	# Locked island: the same plan is refused before Q03 and nothing is placed.
	fresh()
	put(owner,Vector2(44.6,36.7))
	var locked:=world.quote_blueprint(owner,wide.blueprint,DEST,0)
	expect(not locked.ok and bag("stone")==100,"the station blueprint is refused before Q03")

func refund_move_undo_scenario()->void:
	var far:=HOME+Vector2i.RIGHT
	var both:=cells_of(HOME,false)
	unlocked()
	var wood:=bag("wood")
	var stone:=bag("stone")
	var builds:=int(world.state.players[owner].builds)
	act("build",HOME,KIND)
	var made:=world.undo_summary(owner)
	expect(bool(made.get("available",false)),"the build can be undone")
	expect(act(World.UNDO_ACTION,far,str(made.get("id",""))).ok and empty(both) and bag("wood")==wood and bag("stone")==stone and int(world.state.players[owner].builds)==builds,"undo of a build removes both cells and refunds exactly once")
	# Remove from the far end: one refund, both cells.
	unlocked()
	act("build",HOME,KIND)
	var spent_wood:=bag("wood")
	var spent_stone:=bag("stone")
	var removed:=act("remove",far)
	expect(removed.ok and empty(both) and bag("wood")==spent_wood+8 and bag("stone")==spent_stone+20,"dismantling from the far end removes both cells and refunds once")
	expect(not act("remove",far).ok and not act("remove",HOME).ok and bag("wood")==spent_wood+8 and bag("stone")==spent_stone+20,"neither end claims a second refund")
	var removal:=world.undo_summary(owner)
	expect(bool(removal.get("available",false)),"the dismantle can be undone")
	put(guest,centre(far))
	var blocked_undo:=act(World.UNDO_ACTION,HOME,str(removal.get("id","")))
	expect(not blocked_undo.ok and blocked_undo.message==World.UNDO_MSG_OCCUPIED and empty(both),"undo will not restore a solid station onto a player standing on its far end")
	put(guest,Vector2(49.5,39.5))
	expect(act(World.UNDO_ACTION,HOME,str(removal.get("id",""))).ok and parts_ok(HOME,false) and bag("wood")==spent_wood and bag("stone")==spent_stone,"undo restores both cells and reverses the refund")
	# Undo still works on a world where Q03 is no longer true (the unlock never blocks a restore).
	var restore_removed:=act("remove",HOME)
	expect(restore_removed.ok,"the restored station dismantles normally")
	var again:=world.undo_summary(owner)
	world.state.board=false
	world.state.erase(S.PROJECT_KEY)
	if bool(again.get("available",false)):
		expect(act(World.UNDO_ACTION,HOME,str(again.get("id",""))).ok and parts_ok(HOME,false),"restoring a station never looks at the unlock")
	else:expect(false,"the second dismantle is undoable")
	# Orphaned far cell: nothing to refund, nothing crashes.
	unlocked()
	act("build",HOME,KIND)
	world.state.objects.erase(World.key(HOME))
	var orphan_stone:=bag("stone")
	expect(not act("remove",far).ok and bag("stone")==orphan_stone and world.state.objects.has(World.key(far)),"a lone far cell can never be dismantled for a refund")
	expect(not valid(world.state.duplicate(true)),"a lone far cell is not a valid world")
	world.state.objects.erase(World.key(far))
	# Move from the far end: both cells travel, free, parts intact; refusals are atomic.
	unlocked()
	act("build",HOME,KIND)
	var cost_stone:=bag("stone")
	var dest_cells:=cells_of(DEST,false)
	put(owner,Vector2(42.6,36.8))
	var moved:=act("move_object",far,World.key(DEST))
	expect(moved.ok and empty(both) and parts_ok(DEST,false) and all_blocked(dest_cells,true) and all_blocked(both,false),"moving from the far end carries both cells")
	expect(bag("stone")==cost_stone,"moving costs nothing")
	put_chest(HOME+Vector2i(1,0),{})
	var occupied:=snapshot_of(dest_cells)
	var refused:=act("move_object",DEST,World.key(HOME))
	expect(not refused.ok and snapshot_of(dest_cells)==occupied and parts_ok(DEST,false),"a move onto an occupied far cell is refused whole")
	world.state.objects.erase(World.key(HOME+Vector2i(1,0)))
	put(guest,centre(HOME+Vector2i(1,0)))
	expect(not act("move_object",DEST,World.key(HOME)).ok and snapshot_of(dest_cells)==occupied,"a move onto a standing player is refused")
	put(guest,Vector2(46.2,36.6))
	expect(not act("move_object",DEST,World.key(HOME),guest).ok and snapshot_of(dest_cells)==occupied,"a friend standing beside it cannot move the owner's station")
	put(guest,Vector2(49.5,39.5))

func save_scenario()->void:
	var far:=HOME+Vector2i.RIGHT
	unlocked()
	act("build",HOME,KIND)
	world._build_piece(owner,TALL,KIND,true,false,true,true)
	expect(world.save(),"the world saves")
	var saved:=World.new()
	expect(saved.load_world(path) and not saved.recovered_from_backup,"the world reloads from its primary save")
	expect(parts_ok_in(saved,HOME,false) and parts_ok_in(saved,TALL,true),"horizontal and vertical stations survive a reload with parts intact")
	expect(saved.blocked(HOME) and saved.blocked(far) and saved.blocked(TALL+Vector2i.DOWN),"collision survives a reload on every cell")
	expect(saved.state.board==true,"Q03 (the unlock) survives the reload")
	var good:=world.state.duplicate(true)
	expect(valid(good),"the fixture validates")
	var hk:=World.key(HOME)
	var fk:=World.key(far)
	var cases:={}
	var lost_far:=good.duplicate(true);lost_far.objects.erase(fk);cases["far cell missing"]=lost_far
	var lost_head:=good.duplicate(true);lost_head.objects.erase(hk);cases["anchor missing"]=lost_head
	var stranger:=good.duplicate(true);stranger.objects[fk].owner=guest;cases["far cell owned by someone else"]=stranger
	var swapped:=good.duplicate(true);swapped.objects[hk][FIELD]=1;cases["anchor marked as the far end"]=swapped
	var tilted:=good.duplicate(true);tilted.objects[hk][VFIELD]=true;cases["orientation on only one cell"]=tilted
	var too_far:=good.duplicate(true);too_far.objects[fk][FIELD]=2;cases["part out of range"]=too_far
	var text:=good.duplicate(true);text.objects[fk][FIELD]="1";cases["part is text"]=text
	var bare:=good.duplicate(true);bare.objects[fk].erase(FIELD);cases["far cell unmarked"]=bare
	var alien:=good.duplicate(true);alien.objects[World.key(Vector2i(40,38))]={"type":"chest","owner":owner,"items":{},FIELD:0};cases["marker on a chest"]=alien
	var odd_flag:=good.duplicate(true);odd_flag.objects[hk][VFIELD]="yes";cases["orientation is text"]=odd_flag
	var stocked:=good.duplicate(true);stocked.objects[fk].items={"wood":1};cases["far cell carrying items"]=stocked
	var working:=good.duplicate(true);working.objects[fk].job={"x":1};cases["far cell carrying a job"]=working
	for label:String in cases:expect(not valid(cases[label]),"the validator rejects: "+label)
	var document:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	expect(document is Dictionary,"fixture: the save parses")
	if document is Dictionary:
		(document.objects as Dictionary).erase(fk)
		var damaged:=path+".corrupt"
		var handle:=FileAccess.open(damaged,FileAccess.WRITE)
		handle.store_string(JSON.stringify(document))
		handle.close()
		expect(not World.new().load_world(damaged),"a save with half a station is rejected instead of loaded")

func run()->void:
	path="user://stone-workbench-%d.json"%Time.get_ticks_usec()
	world=World.new()
	world.save_path=path
	world.add_player(owner,"石工")
	world.add_player(guest,"旅客")
	world.state.time=720.0
	for x in range(38,51):
		for y in range(33,41):world.state.removed[World.key(Vector2i(x,y))]=true
	fresh()
	contract_scenario()
	progression_scenario()
	direct_build_scenario()
	interaction_scenario()
	q05_scenario()
	stone_routes_scenario()
	existing_pieces_scenario()
	blueprint_scenario()
	refund_move_undo_scenario()
	save_scenario()
	finish()
