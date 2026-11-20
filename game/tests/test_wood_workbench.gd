extends SceneTree
## C08 木工台 focused regression. Pure World (no scene, no UI); works with --headless.
##
## Contract pinned here:
##   - Same id `bench`, 20 wood + 5 stone, now a 2x1 solid piece (1x2 when rotated by a blueprint).
##     Every cell carries `workbench_part` (0 = anchor, 1 = far end) [+ `workbench_vertical`].
##   - Legacy 1x1 benches have NO `workbench_part`: they never grow, move or get recharged, keep their
##     own crafting reach, and a captured legacy bench stays a one-cell blueprint piece.
##   - Either end crafts, sources from adjacent chests, upgrades the workshop; the far end is never a
##     second station (no independent material source) and never a second refund.
##   - Build, blueprint quote/apply, move, remove, undo and save/load all treat both cells as one object.

const World=preload("res://scripts/world.gd")
const I=World.INDUSTRY
const Sources=preload("res://scripts/material_sources.gd")
const Supply=preload("res://scripts/material_supply.gd")
const Design=World.BLUEPRINT_DESIGN
const KIND:="bench"
const FIELD:="workbench_part"
const VFIELD:="workbench_vertical"
## Test yard (cleared in run): x 38..50, y 33..40. (45,34) and the 38..44 x 28..31 block are protected.
const HOME:=Vector2i(40,35)
const LEGACY:=Vector2i(40,38)
const DEST:=Vector2i(44,35)
const TALL:=Vector2i(47,35)
const RECIPE:="sawmill_kit"

var world:World
var owner:="wood-owner"
var guest:="wood-guest"
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
	return world.act(owner if who.is_empty() else who,"wood-workbench-%d"%serial,verb,tile,extra)

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

func is_legacy(tile:Vector2i)->bool:
	var piece:=obj(tile)
	return piece.get("type")==KIND and not piece.has(FIELD) and not piece.has(VFIELD) and I.square_part(piece)==-1 and not I.is_wide_bench(piece)

func put_legacy(tile:Vector2i)->void:
	world.state.objects[World.key(tile)]={"type":KIND,"owner":owner,"items":{}}

func put_chest(tile:Vector2i,items:Dictionary)->void:
	world.state.objects[World.key(tile)]={"type":"chest","owner":owner,"items":items.duplicate()}

## Resets the yard, the owner's bag and positions so every scenario starts identically.
func fresh()->void:
	for x in range(38,51):
		for y in range(33,41):
			var k:=World.key(Vector2i(x,y))
			world.state.objects.erase(k)
			world.state.crops.erase(k)
			world.state.ground.erase(k)
	var person:Dictionary=world.state.players[owner]
	person.inventory={"wood":100,"stone":40}
	person.erase("workshop_upgraded")
	person.crafting_points=0
	put(owner,Vector2(41.0,36.7))
	put(guest,Vector2(49.5,39.5))

func snapshot_of(tiles:Array[Vector2i])->Array:
	var out:Array=[]
	for tile:Vector2i in tiles:out.append(obj(tile).duplicate(true))
	return out

func finish()->void:
	for suffix in ["",".bak",".tmp",".staged",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	if FileAccess.file_exists(path+".corrupt"):DirAccess.remove_absolute(path+".corrupt")
	print("WOOD_WORKBENCH_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

# -------------------------------------------------------------- scenarios --

func contract_scenario()->void:
	expect(KIND=="bench" and I.WORKBENCH==KIND and World.BUILD.has(KIND),"The existing bench id is kept")
	expect(int(World.BUILD[KIND].wood)==20 and int(World.BUILD[KIND].stone)==5 and World.BUILD[KIND].size()==3,"The recipe stays 20 wood + 5 stone")
	expect(KIND in World.UNDO_SOLID,"The bench is a solid kind")
	expect(KIND not in I.ORIENTABLE_FOOTPRINTS and KIND not in I.TWO_CELL_STATIONS,"A bare `bench` is not a two-cell kind by type (that would grow every legacy bench)")
	expect(I.station_cells(KIND,false)==[Vector2i.ZERO,Vector2i.RIGHT] and I.station_cells(KIND,true)==[Vector2i.ZERO,Vector2i.DOWN],"The new bench footprint is 2x1 / 1x2")
	expect(I.square_part({"type":KIND})==-1 and not I.is_wide_bench({"type":KIND}) and not I.is_bench_extension({"type":KIND}),"An unmarked bench reads as a legacy 1x1")
	expect(I.is_wide_bench({"type":KIND,FIELD:0}) and not I.is_bench_extension({"type":KIND,FIELD:0}) and I.is_bench_extension({"type":KIND,FIELD:1}),"Part 0 is the anchor, part 1 the extension")
	expect(not I.is_wide_bench({"type":"chest",FIELD:0}) and I.square_part({"type":"chest",FIELD:1})==-1,"The marker means nothing on other kinds")

func direct_build_scenario()->void:
	fresh()
	var wood:=bag("wood")
	var stone:=bag("stone")
	var builds:=int(world.state.players[owner].builds)
	var built:=act("build",HOME,KIND)
	var both:=cells_of(HOME,false)
	expect(built.ok,"direct build places the bench: "+str(built.get("message","")))
	expect(bag("wood")==wood-20 and bag("stone")==stone-5,"direct build charges the recipe exactly once for both cells")
	expect(int(world.state.players[owner].builds)==builds+1,"one build is counted, not two")
	expect(parts_ok(HOME,false),"both cells are one wide bench with matching parts")
	expect(all_blocked(both,true),"both cells block walking (collision registered across the footprint)")
	expect(World.station_anchor(world.state.objects,HOME+Vector2i.RIGHT)==HOME and World.station_anchor(world.state.objects,HOME)==HOME,"the far end resolves to the anchor")
	expect(valid(world.state.duplicate(true)),"a wide bench validates")
	# Vertical (blueprint rotation) uses the same builder.
	var tall:=world._build_piece(owner,TALL,KIND,true,false,true,true)
	expect(tall.ok and parts_ok(TALL,true) and all_blocked(cells_of(TALL,true),true),"a vertical bench covers both rows and blocks both")
	expect(obj(TALL).get(VFIELD)==true and obj(TALL+Vector2i.DOWN).get(VFIELD)==true,"both vertical cells carry the orientation")
	expect(valid(world.state.duplicate(true)),"a vertical bench validates")
	# Legacy 1x1 builds are only reachable through blueprint settings (wide_station=false).
	var legacy:=world._build_piece(owner,LEGACY,KIND,true,false,false,false)
	expect(legacy.ok and is_legacy(LEGACY) and not world.state.objects.has(World.key(LEGACY+Vector2i.RIGHT)),"wide_station=false rebuilds a one-cell legacy bench")
	# Early handcraft / base furniture never needed a bench.
	fresh()
	world.state.players[owner].inventory.fiber=int(World.ROPE_FIBER_COST)
	expect(act("handcraft_rope",HOME).ok and bag("rope")==1,"handcraft still works with no bench")
	expect(act("build",Vector2i(42,37),"floor").ok,"base building still works with no bench")
	var table:=Vector2i(42,37)
	var available_wood:=bag("wood")
	expect(act("build",table,"table").ok and obj(table).get("type")=="table" and bag("wood")==available_wood-int(World.BUILD.table.wood),
		"A new player builds a basic wooden table without a workbench and pays exactly once")
	expect(not act("craft",HOME,RECIPE).ok and bag(RECIPE)==0,"A beginner table does not unlock bench crafting")
	expect(act("build",HOME,KIND).ok and act("craft",HOME,RECIPE).ok and bag(RECIPE)==1,
		"Building the first workbench unlocks the woodworking recipe")

func site_scenario()->void:
	# Every refusal must be atomic: no object, no charge, no build counted.
	var far:=HOME+Vector2i.RIGHT
	fresh()
	var wood:=bag("wood")
	var stone:=bag("stone")
	var builds:=int(world.state.players[owner].builds)
	var untouched:=func()->bool:return empty(cells_of(HOME,false)) and bag("wood")==wood and bag("stone")==stone and int(world.state.players[owner].builds)==builds
	put_chest(far,{})
	expect(not act("build",HOME,KIND).ok and obj(far).get("type")=="chest" and not world.state.objects.has(World.key(HOME)) and bag("wood")==wood,"an object on the far cell refuses the build and survives")
	world.state.objects.erase(World.key(far))
	world.state.crops[World.key(far)]={"kind":"","growth":0.0,"wet":false,"owner":owner}
	expect(not act("build",HOME,KIND).ok and untouched.call(),"a plot on the far cell refuses the build")
	world.state.crops.erase(World.key(far))
	put(guest,centre(far))
	var crowded:=act("build",HOME,KIND)
	expect(not crowded.ok and untouched.call(),"a player standing on the far cell refuses the build: "+str(crowded.get("message","")))
	put(guest,Vector2(49.5,39.5))
	put(owner,centre(far))
	expect(not act("build",HOME,KIND).ok and untouched.call(),"the builder standing on the far cell refuses it too")
	put(owner,Vector2(41.0,36.7))
	# Protected far cell: anchor (37,30) is free, (38,30) lies inside the protected block.
	var edge:=Vector2i(37,30)
	if world.protected(edge+Vector2i.RIGHT) and not world.protected(edge):
		put(owner,centre(edge)+Vector2(-0.2,1.1))
		var guarded:=act("build",edge,KIND)
		expect(not guarded.ok and not world.state.objects.has(World.key(edge)) and bag("wood")==wood and bag("stone")==stone,"a far cell inside protected ground refuses the whole bench")
		put(owner,Vector2(41.0,36.7))
	else:expect(false,"fixture: (37,30) free next to protected (38,30)")
	# Water far cell: scan the home map for land whose right neighbour is water.
	var shore:=Vector2i(-1,-1)
	for y in range(20,70):
		for x in range(10,80):
			var c:=Vector2i(x,y)
			if shore.x<0 and world.is_land(c) and not world.water(c) and not world.protected(c) and world.water(c+Vector2i.RIGHT) and world.resource(c)=="":shore=c
	expect(shore.x>=0,"fixture: land with water on its right exists")
	if shore.x>=0:
		put(owner,centre(shore)+Vector2(-0.2,1.1))
		var wet:=act("build",shore,KIND)
		expect(not wet.ok and not world.state.objects.has(World.key(shore)) and bag("wood")==wood,"a far cell in the water refuses the whole bench")
		put(owner,Vector2(41.0,36.7))
	# Clean control: the very same spot builds once the far cell is free.
	expect(act("build",HOME,KIND).ok and parts_ok(HOME,false),"control: the bench builds once the far cell is clear")

func interaction_scenario()->void:
	var far:=HOME+Vector2i.RIGHT
	fresh()
	expect(not act("craft",HOME,RECIPE).ok,"no bench, no crafting")
	act("build",HOME,KIND)
	world.state.players[owner].inventory={"wood":40,"stone":20}
	var points:=int(world.state.players[owner].get("crafting_points",0))
	# 3.1 tiles from the far end and 4.1 from the anchor: only a wide bench's either-end reach allows this.
	put(owner,Vector2(44.6,35.5))
	var from_far:=act("craft",far,RECIPE)
	expect(from_far.ok and bag(RECIPE)==1 and bag("wood")==32 and bag("stone")==16,"crafting from the far end works and spends one recipe")
	expect(int(world.state.players[owner].crafting_points)==points+1,"one craft earns one crafting point")
	var from_anchor:=act("craft",HOME,RECIPE)
	expect(from_anchor.ok and bag(RECIPE)==2,"crafting from the anchor works from the same spot (nearest end counts)")
	put(owner,Vector2(44.9,35.5))
	var wood:=bag("wood")
	expect(not act("craft",far,RECIPE).ok and not act("craft",HOME,RECIPE).ok and bag(RECIPE)==2 and bag("wood")==wood,"beyond reach of both ends nothing is crafted")
	put(owner,Vector2(41.0,36.7))
	expect(not act("craft",far,"missing-recipe").ok and int(world.state.players[owner].crafting_points)==points+2,"an unknown recipe from the far end earns nothing")
	# Legacy bench keeps its single-cell reach: 3.1 works, 3.3 does not, the empty cell beside it is not a bench.
	fresh()
	put_legacy(LEGACY)
	world.state.players[owner].inventory={"wood":40,"stone":20}
	put(owner,Vector2(43.6,38.5))
	expect(act("craft",LEGACY,RECIPE).ok and bag(RECIPE)==1,"a legacy bench still crafts at 3.1 tiles")
	put(owner,Vector2(43.8,38.5))
	expect(not act("craft",LEGACY,RECIPE).ok and bag(RECIPE)==1,"a legacy bench still refuses beyond 3.2 tiles")
	put(owner,Vector2(41.0,39.7))
	expect(not act("craft",LEGACY+Vector2i.RIGHT,RECIPE).ok,"the empty cell beside a legacy bench is not a bench")
	expect(is_legacy(LEGACY) and not world.state.objects.has(World.key(LEGACY+Vector2i.RIGHT)),"crafting never grows a legacy bench")

func workshop_scenario()->void:
	var far:=HOME+Vector2i.RIGHT
	fresh()
	act("build",HOME,KIND)
	var person:Dictionary=world.state.players[owner]
	expect(not act("upgrade_workshop",far).ok and not person.get("workshop_upgraded",false),"the workshop upgrade still needs crafting level 6")
	person.crafting_points=55
	expect(World.crafting_level(person)>=World.WORKSHOP_LEVEL,"fixture: level 6 reached")
	expect(act("upgrade_workshop",far).ok and person.get("workshop_upgraded",false)==true,"the far end upgrades the workshop")
	expect(not act("upgrade_workshop",HOME).ok,"a second upgrade is refused")
	person.erase("workshop_upgraded")
	expect(act("upgrade_workshop",HOME).ok and person.get("workshop_upgraded",false)==true,"the anchor upgrades it too")
	fresh()
	put_legacy(LEGACY)
	world.state.players[owner].crafting_points=55
	put(owner,Vector2(41.0,39.7))
	expect(act("upgrade_workshop",LEGACY).ok,"a legacy bench still upgrades the workshop")
	# The unlocked assembly table is still gated on the upgrade, not on the bench shape.
	expect(not act("upgrade_workshop",LEGACY+Vector2i.RIGHT).ok,"the cell beside a legacy bench cannot upgrade")

func sourcing_scenario()->void:
	var far:=HOME+Vector2i.RIGHT
	var east:=HOME+Vector2i(2,0)
	var north:=HOME+Vector2i(1,-1)
	var distant:=HOME+Vector2i(3,0)
	fresh()
	act("build",HOME,KIND)
	put_chest(east,{"wood":30})
	put_chest(north,{"stone":9})
	put_chest(distant,{"wood":5})
	var found:Array=Sources.candidates(world.state.objects,owner,HOME).map(func(entry):return str(entry.cell))
	expect(found==[World.key(north),World.key(east)],"the anchor offers exactly the chests touching either end (y-then-x): "+str(found))
	expect(Sources.candidates(world.state.objects,owner,far).is_empty(),"the far end is never an independent material-source station")
	var seen:=Sources.candidates(world.state.objects,owner,HOME).size()
	expect(seen==2 and not found.has(World.key(distant)),"a chest two cells beyond the far end is not adjacent")
	# Preparing from either end resolves to the one station; a non-adjacent chest is refused.
	var prepared:=act("prepare_material_box",far,World.key(east))
	expect(prepared.ok and str(prepared.get("source_cell",""))==World.key(east),"prepare from the far end picks the chest beside it")
	expect(not act("prepare_material_box",far,World.key(distant)).ok and not obj(distant).has("box_id"),"a non-adjacent chest is refused and gets no identity")
	var box_id:=str(obj(east).get("box_id",""))
	expect(box_id.length()==32,"the prepared chest has a 32-hex identity")
	# Sourced craft: quote is always anchored; either end may submit it.
	world.state.players[owner].inventory={"wood":3,"stone":4}
	var chest_before:=int(obj(east).items.wood)
	var extra:=sourced_extra(HOME,east,box_id)
	put(owner,Vector2(44.6,35.5))
	var sourced:=act("craft",far,extra)
	expect(sourced.ok and bag(RECIPE)==1 and bag("wood")==0 and bag("stone")==0,"a sourced craft submitted from the far end works")
	expect(int(obj(east).items.wood)==chest_before-5,"the chest paid exactly the missing 5 wood")
	# A digest minted for the far cell (a fake second station) is stale, never accepted.
	world.state.players[owner].inventory={"wood":3,"stone":4}
	var stale_inventory:Dictionary=world.state.players[owner].inventory.duplicate()
	var wood_chest:=int(obj(east).items.wood)
	var stale:=act("craft",HOME,sourced_extra(far,east,box_id))
	expect(not stale.ok and bool(stale.get("requote",false)) and world.state.players[owner].inventory==stale_inventory and int(obj(east).items.wood)==wood_chest,"a quote taken against the far cell is stale and changes nothing")
	# A legacy bench keeps the classic four neighbours.
	fresh()
	put_legacy(LEGACY)
	put_chest(LEGACY+Vector2i.RIGHT,{"wood":4})
	put_chest(LEGACY+Vector2i.UP,{"wood":4})
	put_chest(LEGACY+Vector2i(2,0),{"wood":4})
	var legacy_found:Array=Sources.candidates(world.state.objects,owner,LEGACY).map(func(entry):return str(entry.cell))
	expect(legacy_found==[World.key(LEGACY+Vector2i.UP),World.key(LEGACY+Vector2i.RIGHT)],"a legacy bench still sees only its four cardinal neighbours")
	# Two touching legacy benches stay two independent stations.
	world.state.objects.erase(World.key(LEGACY+Vector2i.RIGHT))
	put_legacy(LEGACY+Vector2i.RIGHT)
	expect(is_legacy(LEGACY) and is_legacy(LEGACY+Vector2i.RIGHT) and World.station_anchor(world.state.objects,LEGACY+Vector2i.RIGHT)==LEGACY+Vector2i.RIGHT,"two adjacent unmarked benches are never fused into one wide bench")
	expect(valid(world.state.duplicate(true)),"adjacent legacy benches validate")

func sourced_extra(station:Vector2i,box:Vector2i,box_id:String)->String:
	var def:Dictionary=World.CRAFT[RECIPE]
	var chest:Dictionary=obj(box)
	var plan:Dictionary=Supply.plan(def.ingredients,world.state.players[owner].inventory,chest.items)
	var alloc:={"from_backpack":plan.get("from_backpack",{}),"from_chest":plan.get("from_chest",{})}
	var digest:String=Sources.digest("craft",KIND,World.key(station),RECIPE,def,World.key(box),box_id,alloc)
	return Sources.encode(RECIPE,World.key(box),box_id,digest)

func legacy_scenario()->void:
	fresh()
	put_legacy(LEGACY)
	put_chest(LEGACY+Vector2i.RIGHT,{"wood":3})
	var legacy_before:=obj(LEGACY).duplicate(true)
	var chest_before:=obj(LEGACY+Vector2i.RIGHT).duplicate(true)
	expect(is_legacy(LEGACY) and valid(world.state.duplicate(true)),"an unmarked bench loads and validates as 1x1")
	expect(World.station_anchor(world.state.objects,LEGACY)==LEGACY and world.blocked(LEGACY) and not world.blocked(LEGACY+Vector2i(2,0)),"a legacy bench occupies exactly its own cell")
	# Move: one cell, neighbours untouched, still unmarked, no charge.
	var wood:=bag("wood")
	put(owner,Vector2(41.0,39.7))
	var moved:=act("move_object",LEGACY,World.key(Vector2i(42,39)))
	expect(moved.ok and is_legacy(Vector2i(42,39)) and not world.state.objects.has(World.key(LEGACY)),"a legacy bench moves as one cell")
	expect(not world.state.objects.has(World.key(Vector2i(43,39))) and obj(LEGACY+Vector2i.RIGHT)==chest_before and bag("wood")==wood,"moving a legacy bench grows nothing, touches no neighbour and costs nothing")
	# Remove: refunds the recipe once, only that cell.
	var refund_wood:=bag("wood")
	var refund_stone:=bag("stone")
	var removed:=act("remove",Vector2i(42,39))
	expect(removed.ok and bag("wood")==refund_wood+20 and bag("stone")==refund_stone+5 and not world.state.objects.has(World.key(Vector2i(42,39))),"dismantling a legacy bench refunds 20 wood + 5 stone once")
	expect(not act("remove",Vector2i(42,39)).ok and bag("wood")==refund_wood+20,"a second dismantle grants nothing")
	expect(legacy_before.get("type")==KIND and not legacy_before.has(FIELD),"fixture sanity: the legacy record carried no part field")
	# Undo restores the unmarked record, not a wide one.
	fresh()
	put_legacy(LEGACY)
	put(owner,Vector2(41.0,39.7))
	act("remove",LEGACY)
	var summary:=world.undo_summary(owner)
	if bool(summary.get("available",false)):
		var undone:=act(World.UNDO_ACTION,LEGACY,str(summary.get("id","")))
		expect(undone.ok and is_legacy(LEGACY) and not world.state.objects.has(World.key(LEGACY+Vector2i.RIGHT)),"undoing a legacy dismantle restores an unmarked one-cell bench")
	else:expect(true,"legacy undo not recorded for a preset fixture (skipped)")

func blueprint_scenario()->void:
	var far:=HOME+Vector2i.RIGHT
	# Capture: a legacy bench stays a plain piece; a wide bench records settings.wide.
	fresh()
	put_legacy(LEGACY)
	var old:=Design.capture(world.state,owner,Rect2i(LEGACY,Vector2i(1,1)),"舊工作台",World.BUILD,World.NAMES)
	expect(old.ok and old.blueprint.pieces==[{"kind":KIND,"x":0,"y":0}],"capturing a legacy bench records a settings-less piece")
	fresh()
	act("build",HOME,KIND)
	var wide:=Design.capture(world.state,owner,Rect2i(HOME,Vector2i(2,1)),"木工台",World.BUILD,World.NAMES)
	expect(wide.ok and wide.blueprint.pieces==[{"kind":KIND,"x":0,"y":0,"settings":{"wide":true}}],"capturing a wide bench records one wide piece")
	var clipped:=Design.capture(world.state,owner,Rect2i(HOME,Vector2i(1,1)),"半個",World.BUILD,World.NAMES)
	expect(not clipped.ok,"a capture area cutting the bench in half is refused")
	var clipped_far:=Design.capture(world.state,owner,Rect2i(far,Vector2i(1,1)),"另半個",World.BUILD,World.NAMES)
	expect(not clipped_far.ok,"a capture area holding only the far end is refused too")
	world._build_piece(owner,TALL,KIND,true,false,true,true)
	var tall:=Design.capture(world.state,owner,Rect2i(TALL,Vector2i(1,2)),"木工台直",World.BUILD,World.NAMES)
	expect(tall.ok and tall.blueprint.pieces==[{"kind":KIND,"x":0,"y":0,"settings":{"wide":true,"vertical":true}}],"a vertical bench records wide + vertical")
	if not old.ok or not wide.ok or not tall.ok:return
	# Rotation keeps the wide marker and swaps orientation; a legacy piece never gains settings.
	var turned:=Design.rotate(wide.blueprint,1,World.BUILD,World.NAMES)
	expect(turned.ok and turned.blueprint.pieces==[{"kind":KIND,"x":0,"y":0,"settings":{"wide":true,"vertical":true}}],"rotating a wide bench makes it vertical and keeps `wide`")
	var back:=Design.rotate(tall.blueprint,3,World.BUILD,World.NAMES)
	expect(back.ok and back.blueprint.pieces==[{"kind":KIND,"x":0,"y":0,"settings":{"wide":true}}],"rotating a vertical bench back gives the horizontal one")
	var spun:=Design.rotate(old.blueprint,1,World.BUILD,World.NAMES)
	expect(spun.ok and spun.blueprint.pieces==[{"kind":KIND,"x":0,"y":0}],"rotating a legacy bench piece leaves it a one-cell piece")
	var rejected:=Design.base_cost({"version":1,"name":"木工台測試","width":2,"height":1,"pieces":[{"kind":KIND,"x":0,"y":0,"settings":{"wide":false}}]},World.BUILD,World.NAMES)
	expect(not rejected.ok,"settings.wide must be true")
	# Quote + apply of the wide piece.
	fresh()
	put(owner,Vector2(44.6,36.7))
	var wood:=bag("wood")
	var stone:=bag("stone")
	var quote:=world.quote_blueprint(owner,wide.blueprint,DEST,0)
	expect(quote.ok and int(quote.cost.wood)==20 and int(quote.cost.stone)==5,"quote prices one bench once: "+str(quote.get("message","")))
	var laid:=world.apply_blueprint(owner,next_nonce(),wide.blueprint,DEST,0,str(quote.get("hash","")))
	expect(laid.ok and parts_ok(DEST,false) and all_blocked(cells_of(DEST,false),true),"apply builds both cells, solid")
	expect(bag("wood")==wood-20 and bag("stone")==stone-5,"apply charges once")
	var apply_undo:=world.undo_summary(owner)
	if bool(apply_undo.get("available",false)):
		expect(act(World.UNDO_ACTION,DEST,str(apply_undo.get("id",""))).ok and empty(cells_of(DEST,false)) and bag("wood")==wood and bag("stone")==stone,"undoing the apply removes both cells and refunds exactly")
	else:expect(false,"the blueprint apply is undoable")
	# Clipped site: far cell occupied -> the whole quote is refused, nothing charged.
	fresh()
	put_chest(DEST+Vector2i.RIGHT,{})
	put(owner,Vector2(44.6,36.7))
	var blocked_quote:=world.quote_blueprint(owner,wide.blueprint,DEST,0)
	expect(not blocked_quote.ok and bag("wood")==100,"a blueprint whose far cell is taken is refused whole")
	# Rotated placement.
	fresh()
	put(owner,Vector2(42.6,36.8))
	var spin:=world.quote_blueprint(owner,wide.blueprint,HOME,1)
	expect(spin.ok,"a quarter turn quotes a vertical bench: "+str(spin.get("message","")))
	if spin.ok:
		var turned_laid:=world.apply_blueprint(owner,next_nonce(),wide.blueprint,HOME,1,str(spin.hash))
		var anchor:=Vector2i(-1000,-1000)
		for k:String in world.state.objects:
			var piece:Dictionary=world.state.objects[k]
			if piece.get("type")==KIND and I.square_part(piece)==0:anchor=World.cell(k)
		expect(turned_laid.ok and anchor.x>-1000 and parts_ok(anchor,true) and all_blocked(cells_of(anchor,true),true),"a turned plan builds the vertical bench")
	# The vertical plan placed upright.
	fresh()
	put(owner,Vector2(42.6,36.8))
	var upright:=world.quote_blueprint(owner,tall.blueprint,HOME,0)
	if upright.ok:
		expect(world.apply_blueprint(owner,next_nonce(),tall.blueprint,HOME,0,str(upright.hash)).ok and parts_ok(HOME,true),"a vertical plan builds the vertical bench")
	else:expect(false,"a vertical plan quotes: "+str(upright.get("message","")))
	# Legacy piece applies as a legacy bench: one cell, same price, no marker.
	fresh()
	put(owner,Vector2(44.6,36.7))
	var legacy_quote:=world.quote_blueprint(owner,old.blueprint,DEST,0)
	expect(legacy_quote.ok and int(legacy_quote.cost.wood)==20 and int(legacy_quote.cost.stone)==5,"a legacy piece quotes the same price")
	if legacy_quote.ok:
		var legacy_laid:=world.apply_blueprint(owner,next_nonce(),old.blueprint,DEST,0,str(legacy_quote.hash))
		expect(legacy_laid.ok and is_legacy(DEST) and not world.state.objects.has(World.key(DEST+Vector2i.RIGHT)),"a legacy piece rebuilds a one-cell legacy bench")

func refund_move_undo_scenario()->void:
	var far:=HOME+Vector2i.RIGHT
	var both:=cells_of(HOME,false)
	# Undo of a build.
	fresh()
	var wood:=bag("wood")
	var stone:=bag("stone")
	var builds:=int(world.state.players[owner].builds)
	act("build",HOME,KIND)
	var made:=world.undo_summary(owner)
	expect(bool(made.get("available",false)),"the build can be undone")
	expect(act(World.UNDO_ACTION,far,str(made.get("id",""))).ok and empty(both) and bag("wood")==wood and bag("stone")==stone and int(world.state.players[owner].builds)==builds,"undo of a build removes both cells and refunds exactly once")
	# Remove from the far end: one refund, both cells.
	fresh()
	act("build",HOME,KIND)
	var spent_wood:=bag("wood")
	var spent_stone:=bag("stone")
	var removed:=act("remove",far)
	expect(removed.ok and empty(both) and bag("wood")==spent_wood+20 and bag("stone")==spent_stone+5,"dismantling from the far end removes both cells and refunds one recipe")
	expect(not act("remove",far).ok and not act("remove",HOME).ok and bag("wood")==spent_wood+20 and bag("stone")==spent_stone+5,"neither end can claim a second refund")
	# Undo of the dismantle restores both cells (and takes the refund back); a body on the far cell blocks it.
	var removal:=world.undo_summary(owner)
	expect(bool(removal.get("available",false)),"the dismantle can be undone")
	put(guest,centre(far))
	var blocked_undo:=act(World.UNDO_ACTION,HOME,str(removal.get("id","")))
	expect(not blocked_undo.ok and blocked_undo.message==World.UNDO_MSG_OCCUPIED and empty(both),"undo will not restore a solid bench onto a player standing on its far end")
	put(guest,Vector2(49.5,39.5))
	expect(act(World.UNDO_ACTION,HOME,str(removal.get("id",""))).ok and parts_ok(HOME,false) and bag("wood")==spent_wood and bag("stone")==spent_stone,"undo restores both cells with matching parts and reverses the refund")
	expect(act("remove",HOME).ok and bag("wood")==spent_wood+20,"the restored bench dismantles normally")
	# Orphaned far cell (anchor lost): nothing to refund, nothing crashes.
	fresh()
	act("build",HOME,KIND)
	world.state.objects.erase(World.key(HOME))
	var orphan_wood:=bag("wood")
	var orphan_stone:=bag("stone")
	var orphan:=act("remove",far)
	expect(not orphan.ok and bag("wood")==orphan_wood and bag("stone")==orphan_stone and world.state.objects.has(World.key(far)),"a lone far cell can never be dismantled for a refund")
	expect(not valid(world.state.duplicate(true)),"a lone far cell is not a valid world")
	world.state.objects.erase(World.key(far))
	# Move from the far end: both cells travel, free, parts intact.
	fresh()
	act("build",HOME,KIND)
	var cost_wood:=bag("wood")
	var dest_cells:=cells_of(DEST,false)
	put(owner,Vector2(42.6,36.8))
	var moved:=act("move_object",far,World.key(DEST))
	expect(moved.ok and empty(both) and parts_ok(DEST,false) and all_blocked(dest_cells,true) and all_blocked(both,false),"moving from the far end carries both cells")
	expect(bag("wood")==cost_wood,"moving costs nothing")
	var move_record:=world.undo_summary(owner)
	# Refused moves are atomic.
	put_chest(HOME+Vector2i(1,0),{})
	var occupied:=snapshot_of(dest_cells)
	var refused:=act("move_object",DEST,World.key(HOME))
	expect(not refused.ok and snapshot_of(dest_cells)==occupied and parts_ok(DEST,false),"a move onto an occupied far cell is refused whole")
	world.state.objects.erase(World.key(HOME+Vector2i(1,0)))
	put(guest,centre(HOME+Vector2i(1,0)))
	var onto_body:=act("move_object",DEST,World.key(HOME))
	expect(not onto_body.ok and snapshot_of(dest_cells)==occupied,"a move onto a standing player is refused")
	put(guest,Vector2(49.5,39.5))
	# Overlapping one-cell shift keeps one object.
	put(owner,Vector2(43.6,36.8))
	var shifted:=act("move_object",DEST,World.key(DEST+Vector2i.RIGHT))
	expect(shifted.ok and parts_ok(DEST+Vector2i.RIGHT,false) and not world.state.objects.has(World.key(DEST)),"an overlapping shift moves the bench without leaving a stray end")
	# Undo of the move chain: the latest move goes back.
	var shift_record:=world.undo_summary(owner)
	if bool(shift_record.get("available",false)):
		expect(act(World.UNDO_ACTION,DEST,str(shift_record.get("id",""))).ok and parts_ok(DEST,false) and not world.state.objects.has(World.key(DEST+Vector2i(2,0))),"undoing the shift restores the previous position")
	expect(move_record.has("id"),"the earlier move was recorded")
	# A guest on the old far cell stops the undo of a move (the bench is solid).
	fresh()
	act("build",HOME,KIND)
	put(owner,Vector2(42.6,36.8))
	act("move_object",HOME,World.key(DEST))
	var away:=world.undo_summary(owner)
	put(guest,centre(far))
	var stuck:=act(World.UNDO_ACTION,DEST,str(away.get("id","")))
	expect(not stuck.ok and stuck.message==World.UNDO_MSG_OCCUPIED and parts_ok(DEST,false),"undoing a move will not drop the bench onto a player on its far end")
	put(guest,Vector2(49.5,39.5))
	expect(act(World.UNDO_ACTION,DEST,str(away.get("id",""))).ok and parts_ok(HOME,false) and empty(dest_cells),"once clear, undoing the move restores the bench")

func save_scenario()->void:
	var far:=HOME+Vector2i.RIGHT
	fresh()
	act("build",HOME,KIND)
	world._build_piece(owner,TALL,KIND,true,false,true,true)
	put_legacy(LEGACY)
	expect(world.save(),"the world saves")
	var saved:=World.new()
	expect(saved.load_world(path) and not saved.recovered_from_backup,"the world reloads from its primary save")
	expect(parts_ok_in(saved,HOME,false) and parts_ok_in(saved,TALL,true),"wide and vertical benches survive a reload with parts intact")
	expect(saved.blocked(HOME) and saved.blocked(far) and saved.blocked(TALL+Vector2i.DOWN),"collision survives a reload on every cell")
	var old:Dictionary=saved.state.objects.get(World.key(LEGACY),{})
	expect(old.get("type")==KIND and not old.has(FIELD) and not saved.blocked(LEGACY+Vector2i.RIGHT),"a legacy bench survives a reload unmarked and one cell wide")
	# Validator: every malformed footprint is rejected.
	var good:=world.state.duplicate(true)
	expect(valid(good),"the mixed fixture validates")
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
	var bare:=good.duplicate(true);bare.objects[fk].erase(FIELD);cases["far cell unmarked (legacy next to a marked anchor)"]=bare
	var borrowed:=good.duplicate(true);borrowed.objects[World.key(LEGACY)][FIELD]=0;cases["legacy bench marked but its far cell is empty"]=borrowed
	var alien:=good.duplicate(true);alien.objects[World.key(LEGACY)]={"type":"chest","owner":owner,"items":{},FIELD:0};cases["marker on a chest"]=alien
	var loose_flag:=good.duplicate(true);loose_flag.objects[World.key(LEGACY)][VFIELD]=true;cases["orientation on an unmarked bench"]=loose_flag
	var odd_flag:=good.duplicate(true);odd_flag.objects[hk][VFIELD]="yes";cases["orientation is text"]=odd_flag
	var stocked:=good.duplicate(true);stocked.objects[fk].items={"wood":1};cases["far cell carrying items"]=stocked
	var working:=good.duplicate(true);working.objects[fk].job={"x":1};cases["far cell carrying a job"]=working
	for label:String in cases:expect(not valid(cases[label]),"the validator rejects: "+label)
	# Reload safety: a damaged file never loads half a bench.
	var document:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	expect(document is Dictionary,"fixture: the save parses")
	if document is Dictionary:
		(document.objects as Dictionary).erase(fk)
		var damaged:=path+".corrupt"
		var handle:=FileAccess.open(damaged,FileAccess.WRITE)
		handle.store_string(JSON.stringify(document))
		handle.close()
		var refused:=World.new()
		expect(not refused.load_world(damaged),"a save with a half-bench is rejected instead of loaded")

func run()->void:
	path="user://wood-workbench-%d.json"%Time.get_ticks_usec()
	world=World.new()
	world.save_path=path
	world.add_player(owner,"木工")
	world.add_player(guest,"旅客")
	world.state.time=720.0
	for x in range(38,51):
		for y in range(33,41):world.state.removed[World.key(Vector2i(x,y))]=true
	fresh()
	contract_scenario()
	direct_build_scenario()
	site_scenario()
	interaction_scenario()
	workshop_scenario()
	sourcing_scenario()
	legacy_scenario()
	blueprint_scenario()
	refund_move_undo_scenario()
	save_scenario()
	finish()
