extends SceneTree
## C12 公共廚房灶台 focused regression. Pure World (no scene, no UI); works with --headless.
##
## Contract pinned here:
##   - id `kitchen_stove`, 20 stone + 12 wood + 5 clay, a fixed 2x2 solid piece; every cell carries
##     `kitchen_stove_part` 0..3 (0 = anchor). Only the ANCHOR holds the `cooking` queue.
##   - the early single-cell `stove` keeps its id, cost, recipe numbers (soup 10 s ...), legacy `job`
##     path and saves; it cannot cook the C12-only dishes (forest_mushroom_soup, rainbow_skewer).
##   - the C12 stove cooks the canonical D01-D16 numbers (an independent copy of the content bible
##     table is in SPEC below) through the same queue / receipt / permission code.
##   - interaction (cook / claim / cancel) works from any of the four cells and never duplicates an item.
##   - build / blueprint / undo / move / remove / refund treat the four cells as ONE anchor.
##   - Q04: it can be donated through the existing kitchen_register / kitchen_contribute actions (from
##     any cell), the four cells become permanently protected, and the kitchen state survives a reload.
##   - old saves (a legacy stove with a running job, a completed kitchen donated with a legacy stove)
##     still validate, reload and cook with their original numbers.
##
## GEOMETRY. Every action is gated by a 3.2-tile reach measured from the player to the clicked cell's
## centre (for a 2x2 station: to the NEAREST of its four cell centres; a move also needs the DESTINATION
## centre within 3.2). All sites below (OUT_OF_REACH excepted, it is only a far coordinate) are inside the
## island clearing the shipped public layout is built
## in (x 39..44, y 32..36, cleared through `World.state.removed`); geometry_scenario() asserts that they
## are free, unprotected, standable and in / out of reach as claimed, so a fixture can never fail for an
## unnoticed geometric reason. The public layout is the one the native and network drivers use:
## stove anchor (41,33), long benches (40,35) and (43,35) (each covers its cell and the one to its east),
## shared table (39,30), owner at (41.5,36.5).
##
## STORAGE. The queue (`cooking`) lives on the anchor object only. A cell clicked anywhere on the piece is
## resolved to the anchor by World.station_anchor before the action runs. A save is parsed from JSON and
## validated by SaveSchema, so counts come back as whole numbers and `kitchen_stove_part` as a number; the
## checks below compare values, never types.

const World=preload("res://scripts/world.gd")
const I=World.INDUSTRY
const K=World.KITCHEN_STOVE
const PK=World.PUBLIC_KITCHEN
const Design=World.BLUEPRINT_DESIGN
const Community=preload("res://scripts/community.gd")
const KIND:="kitchen_stove"
const FIELD:="kitchen_stove_part"
const BOARD:=Vector2i(40,29)
## Verified clear 2x2 sites in the clearing. HOME is also the public anchor; DEST (east of it) is the move target.
const HOME:=Vector2i(41,33)
const DEST:=Vector2i(43,33)
const OLD:=HOME
const PUB:=HOME
const SEAT1:=Vector2i(40,35)
const SEAT2:=Vector2i(43,35)
## Player spots (all standable): STAND is 3.0 from HOME's anchor centre and 3.6 from DEST's, so it reaches
## HOME but NOT a move onto DEST; MOVER reaches both; EAST / WEST flank the stove; AWAY is a parked bystander;
## OUT_OF_REACH is more than 3.2 from every HOME cell and from DEST.
const STAND:=Vector2(41.5,36.5)
const MOVER:=Vector2(42.5,35.5)
const EAST:=Vector2(43.5,34.5)
const WEST:=Vector2(40.5,34.5)
const BESIDE:=Vector2(43.5,36.5)
const AWAY:=Vector2(39.5,36.5)
const OUT_OF_REACH:=Vector2(41.5,38.5)
const REACH:=3.2
const A:="kitchen-a"
const B:="kitchen-b"

## Independent copy of content bible §11 (D01-D16): id, ingredients, seconds, yield, stamina per serving.
const SPEC:={
	"D01":["soup",{"radish":2},30.0,2,20],
	"D02":["baked_potato",{"potato":2},30.0,2,25],
	"D03":["salad",{"lettuce":1,"tomato":1},30.0,2,20],
	"D04":["bread",{"flour":1},30.0,1,30],
	"D05":["forest_mushroom_soup",{"star_mushroom":2,"chime_herb":1},60.0,2,35],
	"D06":["salt_grilled_fish",{"minnow":1,"sea_salt":1},60.0,1,40],
	"D07":["corn_chowder",{"sweet_corn":2,"milk":1},90.0,3,30],
	"D08":["star_rice_ball",{"rice":2,"seaweed":1},60.0,3,25],
	"D09":["strawberry_toast",{"bread":2,"strawberry_jam":1},30.0,2,30],
	"D10":["pumpkin_pie",{"pumpkin":1,"flour":1,"egg":1},120.0,4,35],
	"D11":["tea_pudding",{"mist_tea":1,"milk":1,"egg":1},120.0,3,30],
	"D12":["ginger_tea",{"ginger":1,"sugar":1},60.0,2,20],
	"D13":["seafood_rice",{"rice":2,"gold_shrimp":1,"minnow":1},120.0,3,45],
	"D14":["rainbow_skewer",{"radish":1,"carrot":1,"eggplant":1},60.0,3,25],
	"D15":["garden_cookie",{"flour":1,"sugar":1,"chime_herb":1},90.0,4,20],
	"D16":["trout_hotpot",{"cabbage":1,"star_mushroom":2,"snow_trout":1},180.0,4,50],
}

var world:World
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

func act(verb:String,tile:Vector2i,extra:="",who:=A,w:World=null)->Dictionary:
	serial+=1
	var target:World=world if w==null else w
	return target.act(who,"kitchen-stove-%d"%serial,verb,tile,extra)

func next_nonce()->String:
	nonce+=1
	return ("%02x"%nonce).repeat(16)

# ---------------------------------------------------------------- helpers --

func valid(state:Dictionary)->bool:
	return bool(World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME))

func bag(item:String,who:=A,w:World=null)->int:
	var target:World=world if w==null else w
	return int(target.state.players[who].inventory.get(item,0))

func put(token:String,at:Vector2,w:World=null)->void:
	var target:World=world if w==null else w
	target.state.players[token].x=at.x
	target.state.players[token].y=at.y

func centre(tile:Vector2i)->Vector2:
	return Vector2(tile)+Vector2(0.5,0.5)

## Distance the reach gate measures for a 2x2 station anchored at `anchor`: to the nearest cell centre.
func nearest(spot:Vector2,anchor:Vector2i)->float:
	var best:=INF
	for offset:Vector2i in I.station_cells(KIND):best=minf(best,spot.distance_to(centre(anchor+offset)))
	return best

func cells_of(anchor:Vector2i)->Array[Vector2i]:
	var out:Array[Vector2i]=[]
	for offset:Vector2i in I.station_cells(KIND):out.append(anchor+offset)
	return out

func obj_in(w:World,tile:Vector2i)->Dictionary:
	return w.state.objects.get(World.key(tile),{})

func obj(tile:Vector2i)->Dictionary:
	return obj_in(world,tile)

## Every cell is the stove, owned by `who`, numbered 0..3, and only the anchor may carry a queue / job.
func parts_ok_in(w:World,anchor:Vector2i,who:=A)->bool:
	var list:=cells_of(anchor)
	for index in list.size():
		var piece:Dictionary=obj_in(w,list[index])
		if piece.get("type")!=KIND or piece.get("owner")!=who or int(piece.get(FIELD,-1))!=index:return false
		if index>0 and (piece.has("cooking") or piece.has("job")):return false
	return true

func parts_ok(anchor:Vector2i)->bool:
	return parts_ok_in(world,anchor)

func all_blocked(list:Array[Vector2i],expected:bool,w:World=null)->bool:
	var target:World=world if w==null else w
	for tile:Vector2i in list:
		if target.blocked(tile)!=expected or target.can_stand(centre(tile))==expected:return false
	return true

func empty(list:Array[Vector2i])->bool:
	for tile:Vector2i in list:
		if world.state.objects.has(World.key(tile)):return false
	return true

func snapshot_of(tiles:Array[Vector2i])->Array:
	var out:Array=[]
	for tile:Vector2i in tiles:out.append(obj(tile).duplicate(true))
	return out

func setup_player(w:World,token:String,name:String)->void:
	w.add_player(token,name)
	# FIXTURE: explicit stock (not a normal-play balance). clay is the C12 recipe's third material.
	w.state.players[token].inventory=stock()

func stock()->Dictionary:
	return {"wood":500,"stone":300,"fiber":100,"clay":30,"radish":20,"wheat":10,"potato":6,"flour":6,
		"carrot":4,"eggplant":4,"star_mushroom":4,"chime_herb":4}

## The shipped island up to the public-kitchen prerequisites, through the real actions: the clearing is opened,
## the Q03 board is repaired and the picnic table stands (shared table at (39,30)). `tokens[0]` pays.
func open_island(w:World,tokens:Array)->void:
	w.state.time=720.0
	for token:String in tokens:
		var stories:Dictionary=w.state.players[token].get("stories",{})
		stories["aru"]=maxi(2,int(stories.get("aru",0)))
		w.state.players[token]["stories"]=stories
	for x in range(38,51):
		for y in range(32,41):w.state.removed[World.key(Vector2i(x,y))]=true
	put(tokens[0],centre(BOARD)+Vector2(0.0,1.0),w)
	expect(act("donate",BOARD,"",tokens[0],w).ok and w.state.board==true,"fixture: Q03 through the real donate")
	w.state.players[tokens[0]].inventory.merge(World.CHAPTER_ONE.PICNIC_PORTIONS,true)
	var picnic:=act("picnic",BOARD,"",tokens[0],w)
	expect(picnic.ok and w.state.picnic==true,"fixture: the picnic through the real action: "+str(picnic.message))

## Wipes the clearing (objects, plots, floors) and gives both players a fresh bag, off the stove.
func fresh()->void:
	for x in range(38,51):
		for y in range(32,41):
			var k:=World.key(Vector2i(x,y))
			world.state.objects.erase(k)
			world.state.crops.erase(k)
			world.state.ground.erase(k)
	for token:String in [A,B]:
		var person:Dictionary=world.state.players[token]
		person.inventory=stock()
		person.builds=0
		person.mine_energy=100
		person.region=World.REGIONS.HOME
	world.state.public_kitchen=World.SAVE_SCHEMA.public_kitchen_fresh()
	put(A,STAND)
	put(B,AWAY)

func finish()->void:
	for suffix in ["",".bak",".tmp",".staged",".writer-lock",".corrupt"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("KITCHEN_STOVE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

# -------------------------------------------------------------- scenarios --

func contract_scenario()->void:
	var recipe:Dictionary=World.BUILD[KIND]
	expect(I.KITCHEN_STOVE==KIND and World.BUILD.has(KIND),"stable id kitchen_stove is registered")
	expect(recipe.name=="公共廚房灶台" and int(recipe.stone)==20 and int(recipe.wood)==12 and int(recipe.clay)==5 and recipe.size()==4,"cost is exactly 20 stone + 12 wood + 5 clay")
	expect(K.COST=={"stone":20,"wood":12,"clay":5},"the helper's own cost table agrees")
	expect(KIND in World.UNDO_SOLID and KIND in I.FIXED_SQUARE_STATIONS,"solid fixed-square piece (the smelter / kiln family)")
	expect(I.station_cells(KIND)==I.SQUARE_CELLS and I.square_part_field(KIND)==FIELD,"2x2 footprint with part field kitchen_stove_part")
	# The early stove is untouched: id, price, recipe numbers.
	var early:Dictionary=World.BUILD.stove
	expect(early.name=="小石灶" and int(early.wood)==12 and int(early.stone)==15 and early.size()==3,"the early 小石灶 still costs 12 wood + 15 stone")
	expect(int(World.RECIPES.soup.time)==10 and World.RECIPES.bread.ingredients=={"wheat":2} and int(World.RECIPES.bread.time)==15,"old recipe numbers (soup 10 s, bread = 2 wheat 15 s) are unchanged")
	expect(not World.stove_recipes("stove").has("forest_mushroom_soup") and not World.stove_recipes("stove").has("rainbow_skewer"),"the early stove cannot cook the C12-only dishes")
	expect(World.stove_recipes("stove")==K.legacy_recipes(World.RECIPES) and World.stove_recipes("stove").soup==World.RECIPES.soup,"the early stove table is the old table")
	# Sixteen named dishes, canonical numbers, distinct ids only where necessary.
	expect(K.DISHES.size()==16,"sixteen D rows")
	var table:Dictionary=World.stove_recipes(KIND)
	var seen:={}
	for dish:String in SPEC:
		var row:Array=SPEC[dish]
		var id:String=row[0]
		seen[id]=true
		var recipe_row:Dictionary=table.get(id,{})
		expect(not recipe_row.is_empty() and recipe_row.ingredients==row[1] and float(recipe_row.time)==float(row[2]) and int(recipe_row["yield"])==int(row[3]),"%s %s: canonical ingredients / seconds / yield"%[dish,id])
		expect(K.restore_for(id)==int(row[4]),"%s %s: %d stamina per serving"%[dish,id,int(row[4])])
		expect(World.NAMES.has(id) and World.RECIPES.has(id),"%s %s is a registered item and recipe"%[dish,id])
	expect(seen.size()==16,"sixteen distinct dish ids")
	var new_ids:=[]
	for id:String in seen:
		if id in K.EXCLUSIVE:new_ids.append(id)
	new_ids.sort()
	expect(new_ids==["forest_mushroom_soup","rainbow_skewer"],"only D05 and D14 needed new ids")

## The fixture's own claims, checked against the real world: sites are free / unprotected / standable, and the
## reach arithmetic every other scenario relies on is true. A wrong coordinate fails HERE, by name.
func geometry_scenario()->void:
	fresh()
	for anchor:Vector2i in [HOME,DEST]:
		for tile:Vector2i in cells_of(anchor):
			expect(not world.blocked(tile) and not world.protected(tile) and not world.water(tile) and world.resource(tile)=="" and not world.state.objects.has(World.key(tile)),"site cell %s is clear, unprotected, dry and free"%World.key(tile))
	for tile:Vector2i in [SEAT1,SEAT1+Vector2i.RIGHT,SEAT2,SEAT2+Vector2i.RIGHT]:
		expect(not world.blocked(tile) and not world.protected(tile) and world.resource(tile)=="","bench cell %s is clear"%World.key(tile))
	# OUT_OF_REACH is only a coordinate (the world does not ask where an actor stands), so it is not checked for footing.
	for spot:Vector2 in [STAND,MOVER,EAST,WEST,BESIDE,AWAY]:
		expect(world.can_stand(spot),"the player can stand at %s"%str(spot))
	expect(nearest(AWAY,HOME)>0.8 and nearest(AWAY,DEST)>0.8 and AWAY.distance_to(centre(SEAT1))>0.8,"the parked bystander is clear of every site cell and bench")
	expect(nearest(STAND,HOME)<=REACH and STAND.distance_to(centre(HOME))<=REACH,"STAND reaches the HOME anchor")
	expect(STAND.distance_to(centre(DEST))>REACH,"STAND does not reach a move onto DEST")
	expect(nearest(MOVER,HOME)<=REACH and MOVER.distance_to(centre(DEST))<=REACH and nearest(MOVER,DEST)<=REACH,"MOVER reaches both HOME and DEST")
	expect(nearest(EAST,HOME)<=REACH and nearest(WEST,HOME)<=REACH and nearest(BESIDE,HOME)<=REACH,"EAST, WEST and BESIDE reach the stove")
	expect(nearest(OUT_OF_REACH,HOME)>REACH and OUT_OF_REACH.distance_to(centre(DEST))>REACH,"OUT_OF_REACH reaches neither site")
	# The public layout: seats within 3 tiles of the anchor, the table within 8, the table cell is where we say.
	expect(Vector2(SEAT1).distance_to(Vector2(HOME))<=PK.SEAT_RANGE and Vector2(SEAT2).distance_to(Vector2(HOME))<=PK.SEAT_RANGE,"both seats are within the donation range of the anchor")
	expect(Vector2(HOME).distance_to(Vector2(39,30))<=PK.STOVE_RANGE and Community.table_cell(world.state)==Vector2i(39,30),"the shared table is at (39,30), within 8 tiles of the stove")

func build_scenario()->void:
	fresh()
	var wood:=bag("wood")
	var stone:=bag("stone")
	var clay:=bag("clay")
	var builds:=int(world.state.players[A].builds)
	var cells:=cells_of(HOME)
	# Out of reach: refused whole, nothing charged, nothing placed.
	put(A,OUT_OF_REACH)
	var far_away:=act("build",HOME,KIND)
	expect(not far_away.ok and str(far_away.message).contains("靠近") and empty(cells) and bag("stone")==stone and bag("clay")==clay,"building from beyond reach is refused and charges nothing: "+str(far_away.get("message","")))
	put(A,STAND)
	var built:=act("build",HOME,KIND)
	expect(built.ok and parts_ok(HOME),"build lays four parts: "+str(built.get("message","")))
	expect(bag("stone")==stone-20 and bag("wood")==wood-12 and bag("clay")==clay-5 and int(world.state.players[A].builds)==builds+1,"it cost exactly 20 stone + 12 wood + 5 clay, one build")
	expect(all_blocked(cells,true),"all four cells are solid")
	expect(not obj(HOME).has("cooking") and not obj(HOME).has("job"),"a new stove starts with no queue and no legacy job")
	expect(valid(world.state.duplicate(true)),"the world validates with the stove")
	# A site that is not free is refused whole, nothing charged (MOVER reaches DEST, so occupation is the only reason).
	var before:=bag("stone")
	put(A,MOVER)
	world.state.objects[World.key(DEST+Vector2i.ONE)]={"type":"chest","owner":A,"items":{}}
	var clipped:=act("build",DEST,KIND)
	expect(not clipped.ok and str(clipped.message).contains("占地") and bag("stone")==before and not world.state.objects.has(World.key(DEST)),"a clipped site is refused whole and charges nothing: "+str(clipped.get("message","")))
	world.state.objects.erase(World.key(DEST+Vector2i.ONE))
	# Not enough clay: refused, nothing placed.
	world.state.players[A].inventory.clay=4
	expect(not act("build",DEST,KIND).ok and empty(cells_of(DEST)),"4 clay is not enough")
	world.state.players[A].inventory.clay=30

func interaction_scenario()->void:
	fresh()
	var far:=HOME+Vector2i.ONE
	expect(act("build",HOME,KIND).ok,"fixture: stove built")
	var anchor_before:=obj(HOME).duplicate(true)
	# Reach is measured to the nearest of the four cells: out of reach nothing is taken.
	var radish:=bag("radish")
	put(A,OUT_OF_REACH)
	var too_far:=act("queue_cook",far,"soup")
	expect(not too_far.ok and str(too_far.message).contains("靠近") and bag("radish")==radish and not obj(HOME).has("cooking"),"queueing from beyond reach is refused: "+str(too_far.get("message","")))
	# Queue from the FAR corner, standing on its far side.
	put(A,EAST)
	var queued:=act("queue_cook",far,"soup")
	expect(queued.ok,"queue from the far corner: "+str(queued.get("message","")))
	expect(bag("radish")==radish-2,"exactly two radishes were taken, once")
	var queue:Dictionary=obj(HOME).get("cooking",{})
	var active:Dictionary=queue.get("active",{})
	expect(not active.is_empty() and active.kind=="soup" and float(active.duration)==30.0 and int(active["yield"])==2 and active.ingredients=={"radish":2},"the job is the canonical D01: 30 s, 2 portions, 2 radish")
	expect(is_equal_approx(float(active.get("finish",0))-float(world.state.time),30.0),"it is due 30 s after it was queued")
	expect(obj(HOME).has("cooking") and not obj(HOME+Vector2i.RIGHT).has("cooking") and not obj(HOME+Vector2i.DOWN).has("cooking") and not obj(far).has("cooking"),"only the anchor holds a queue; the other cells hold nothing")
	expect(anchor_before!=obj(HOME),"fixture: the anchor changed")
	# A replayed request is a receipt, not a second job (the first use of this id is a WAITING second soup).
	var rid:="kitchen-stove-receipt"
	var first:Dictionary=world.act(A,rid,"queue_cook",HOME+Vector2i.RIGHT,"soup")
	var replay:Dictionary=world.act(A,rid,"queue_cook",HOME+Vector2i.RIGHT,"soup")
	expect(first.ok and replay==first and bag("radish")==radish-4 and (obj(HOME).cooking.waiting as Array).size()==1,"replaying one request id returns the stored receipt and takes the radish only once")
	# The early stove would have finished in 10 s; the canonical job is not due at 29 s.
	expect(world.step(29.0,true) and (obj(HOME).cooking.ready as Array).is_empty(),"not ready after 29 s")
	var early_claim:=act("claim_cook",HOME+Vector2i.DOWN)
	expect(not early_claim.ok and bag("soup")==0,"claiming before it is done gives nothing")
	expect(world.step(2.0,true) and (obj(HOME).cooking.ready as Array).size()==1,"exactly the first dish is ready after 31 s")
	# Claim from a different corner than the one that queued it.
	var claimed:=act("claim_cook",HOME+Vector2i.DOWN)
	expect(claimed.ok and bag("soup")==2,"claiming from another corner gives the 2 portions: "+str(claimed.get("message","")))
	# Every corner again: the second soup is still cooking, so nothing more comes out.
	expect(not act("claim_cook",HOME+Vector2i.DOWN).ok and not act("claim_cook",HOME).ok and not act("claim_cook",far).ok and bag("soup")==2,"no corner can claim the same dish twice")
	# Cancel a WAITING job (by id) from the third corner: refund exactly once. cancel_cook is for the active one.
	world.state.players[A].inventory.soup=0
	var potato:=bag("potato")
	expect(act("queue_cook",HOME,"baked_potato").ok and bag("potato")==potato-2,"a third dish waits behind the running soup")
	var waiting:Array=obj(HOME).cooking.waiting
	var waiting_id:=str(waiting[0].id)
	var cancelled:=act("cancel_queued_cook",HOME+Vector2i.DOWN,waiting_id)
	expect(cancelled.ok and bag("potato")==potato and (obj(HOME).cooking.waiting as Array).is_empty(),"cancelling the waiting dish from another corner refunds exactly the potatoes: "+str(cancelled.get("message","")))
	expect(not act("cancel_queued_cook",HOME+Vector2i.DOWN,waiting_id).ok and bag("potato")==potato,"a second cancel refunds nothing more")
	# Cancel the ACTIVE job from the far corner.
	var running:Dictionary=obj(HOME).cooking.active
	expect(not running.is_empty() and running.kind=="soup" and running.owner==A,"fixture: the soup of the replayed request is the running job")
	var stopped:=act("cancel_cook",far)
	expect(stopped.ok and bag("radish")==radish-2 and (obj(HOME).cooking.active as Dictionary).is_empty(),"cancelling the running job from the far corner refunds its two radishes: "+str(stopped.get("message","")))
	expect(not act("cancel_cook",far).ok and not act("cancel_cook",HOME).ok and bag("radish")==radish-2,"nothing is left to cancel and nothing more is refunded")
	# Canonical numbers beyond D01: bread is one flour (not two wheat), thirty seconds.
	var flour:=bag("flour")
	expect(act("queue_cook",HOME,"bread").ok and bag("flour")==flour-1 and bag("wheat")==10,"D04 bread costs 1 flour on the C12 stove, never wheat")
	var bread_active:Dictionary=obj(HOME).cooking.active
	expect(float(bread_active.duration)==30.0 and int(bread_active["yield"])==1,"D04: 30 s, 1 portion")
	# These dishes require their own previously completed activities.
	expect(not act("queue_cook",HOME,"forest_mushroom_soup").ok,"D05 is locked before the forest commission")
	expect(not act("queue_cook",HOME,"rainbow_skewer").ok,"D14 is locked before learning it at the summer market")
	var cook:Dictionary=world.state.players[A]
	cook[World.FOREST_MUSHROOM.KEY]=World.FOREST_MUSHROOM.STAGE_DONE
	cook[World.SUMMER_MARKET.KEY]={"day":World.SUMMER_MARKET.day_of(world.state.time),"recipe":true,"root":"radish"}
	expect(act("queue_cook",HOME,"forest_mushroom_soup").ok and bag("star_mushroom")==2 and bag("chime_herb")==3,"D05 forest_mushroom_soup cooks on the C12 stove")
	expect(act("queue_cook",HOME,"rainbow_skewer").ok and bag("carrot")==3 and bag("eggplant")==3,"D14 rainbow_skewer cooks on the C12 stove")
	cook.erase(World.FOREST_MUSHROOM.KEY)
	cook.erase(World.SUMMER_MARKET.KEY)
	# ... and an unknown / unowned recipe is refused.
	expect(not act("queue_cook",HOME,"not_a_dish").ok,"an unknown recipe is refused")
	# A friend may use the stove through the same queue permissions (shared stove), but cannot dismantle it.
	put(B,WEST)
	world.state.players[B].inventory.radish=2
	expect(act("queue_cook",HOME+Vector2i.RIGHT,"soup",B).ok and bag("radish",B)==0,"a friend can queue on a private stove (existing stove rule)")
	put(B,MOVER)
	var theft:=act("move_object",far,World.key(DEST),B)
	expect(not theft.ok and theft.message==World.PLOT_PERMISSIONS.MSG_FOREIGN_MOVE and parts_ok(HOME),"a friend in reach of both sites still cannot move it: "+str(theft.get("message","")))
	expect(not act("remove",far,"",B).ok and parts_ok(HOME),"a friend cannot dismantle it")

func eating_scenario()->void:
	fresh()
	var person:Dictionary=world.state.players[A]
	person.inventory={"soup":2,"rainbow_skewer":1,"star_rice_ball":1}
	person.mine_energy=50
	# Outside a mine nothing is eaten and nothing is spent.
	var outside:=act(K.EAT_ACTION,Vector2i.ZERO,"soup")
	expect(not outside.ok and bag("soup")==2 and int(person.mine_energy)==50,"eat_meal needs a mine; nothing is spent outside")
	person.region="mine_1"
	var ate:=act(K.EAT_ACTION,Vector2i.ZERO,"soup")
	expect(ate.ok and bag("soup")==1 and int(person.mine_energy)==70,"D01 restores 20 stamina per serving: "+str(ate.get("message","")))
	person.mine_energy=90
	var capped:=act(K.EAT_ACTION,Vector2i.ZERO,"soup")
	expect(capped.ok and int(person.mine_energy)==100 and bag("soup")==0,"restore never overflows the cap of 100")
	expect(not act(K.EAT_ACTION,Vector2i.ZERO,"soup").ok and bag("soup")==0,"no serving left means no eating")
	person.mine_energy=60
	expect(act(K.EAT_ACTION,Vector2i.ZERO,"rainbow_skewer").ok and int(person.mine_energy)==85,"D14 restores 25")
	person.mine_energy=100
	expect(not act(K.EAT_ACTION,Vector2i.ZERO,"soup").ok,"full stamina refuses and spends nothing")
	# The two dishes with older eating actions keep them (and their numbers) exactly.
	person.mine_energy=50
	expect(not act(K.EAT_ACTION,Vector2i.ZERO,"star_rice_ball").ok and bag("star_rice_ball")==1,"eat_meal does not take over star_rice_ball")
	expect(act("eat_rice_ball",Vector2i.ZERO).ok and int(person.mine_energy)==50+World.RICE_BALL_ENERGY,"the older eat_rice_ball action still restores its original amount")
	expect(not act(K.EAT_ACTION,Vector2i.ZERO,"tea_pudding_not_a_dish").ok and not act(K.EAT_ACTION,Vector2i.ZERO,"flour").ok,"only D01-D16 dishes are edible this way")
	person.region=World.REGIONS.HOME

func refund_move_undo_scenario()->void:
	fresh()
	var far:=HOME+Vector2i.ONE
	var both:=cells_of(HOME)
	var wood:=bag("wood")
	var stone:=bag("stone")
	var clay:=bag("clay")
	var builds:=int(world.state.players[A].builds)
	expect(act("build",HOME,KIND).ok,"fixture: stove built")
	var made:=world.undo_summary(A)
	expect(bool(made.get("available",false)),"the build can be undone")
	expect(act(World.UNDO_ACTION,far,str(made.get("id",""))).ok and empty(both) and bag("wood")==wood and bag("stone")==stone and bag("clay")==clay and int(world.state.players[A].builds)==builds,"undo removes four cells and refunds exactly once")
	# Remove from the far corner: one refund, four cells, no second claim. Out of reach it is refused whole.
	expect(act("build",HOME,KIND).ok,"fixture: stove rebuilt")
	var spent_wood:=bag("wood")
	var spent_stone:=bag("stone")
	var spent_clay:=bag("clay")
	put(A,OUT_OF_REACH)
	expect(not act("remove",far).ok and parts_ok(HOME) and bag("clay")==spent_clay,"dismantling from beyond reach is refused and refunds nothing")
	put(A,STAND)
	var removed:=act("remove",far)
	expect(removed.ok and empty(both) and bag("wood")==spent_wood+12 and bag("stone")==spent_stone+20 and bag("clay")==spent_clay+5,"dismantling from the far corner removes all four cells and refunds once: "+str(removed.get("message","")))
	expect(not act("remove",far).ok and not act("remove",HOME).ok and bag("clay")==spent_clay+5,"no corner claims a second refund")
	var removal:=world.undo_summary(A)
	expect(bool(removal.get("available",false)),"the dismantle can be undone")
	put(B,centre(far))
	var blocked_undo:=act(World.UNDO_ACTION,HOME,str(removal.get("id","")))
	expect(not blocked_undo.ok and blocked_undo.message==World.UNDO_MSG_OCCUPIED and empty(both),"undo will not restore a solid stove onto a player standing on its far corner: "+str(blocked_undo.get("message","")))
	put(B,AWAY)
	expect(act(World.UNDO_ACTION,HOME,str(removal.get("id",""))).ok and parts_ok(HOME) and bag("clay")==spent_clay,"undo restores four cells and reverses the refund")
	# A busy queue blocks move and remove, from any corner (MOVER reaches both sites, so busy is the only reason).
	put(A,MOVER)
	expect(act("queue_cook",HOME,"soup").ok,"fixture: a job is queued")
	var busy:=snapshot_of(both)
	var busy_move:=act("move_object",far,World.key(DEST))
	expect(not act("remove",far).ok and not busy_move.ok and busy_move.message==World.COOKING_MSG_BUSY and snapshot_of(both)==busy,"a stove with a queued dish can be neither removed nor moved: "+str(busy_move.get("message","")))
	expect(world.step(31.0,true),"fixture: time passes")
	var unclaimed:=act("move_object",far,World.key(DEST))
	expect(not unclaimed.ok and unclaimed.message==World.COOKING_MSG_BUSY,"a finished but unclaimed dish still blocks the move: "+str(unclaimed.get("message","")))
	expect(act("claim_cook",far).ok,"fixture: the dish is claimed")
	# Move from the far corner: four cells travel, free, queue-free anchor intact; refusals are atomic.
	var cost_clay:=bag("clay")
	put(A,STAND)
	var settled:=snapshot_of(both)
	var short:=act("move_object",far,World.key(DEST))
	expect(not short.ok and str(short.message).contains("三格") and snapshot_of(both)==settled and parts_ok(HOME) and empty(cells_of(DEST)),"a destination beyond reach is refused whole: "+str(short.get("message","")))
	put(A,MOVER)
	var moved:=act("move_object",far,World.key(DEST))
	expect(moved.ok and empty(both) and parts_ok(DEST) and all_blocked(cells_of(DEST),true) and all_blocked(both,false),"moving from the far corner carries all four cells: "+str(moved.get("message","")))
	expect(bag("clay")==cost_clay,"moving costs nothing")
	expect(obj(DEST).has("cooking") and World.cooking_idle(obj(DEST)),"the moved anchor keeps its (empty) queue")
	world.state.objects[World.key(HOME+Vector2i.ONE)]={"type":"chest","owner":A,"items":{}}
	var occupied:=snapshot_of(cells_of(DEST))
	var refused:=act("move_object",DEST,World.key(HOME))
	expect(not refused.ok and str(refused.message).contains("占地") and snapshot_of(cells_of(DEST))==occupied and parts_ok(DEST),"a move onto an occupied corner is refused whole: "+str(refused.get("message","")))
	world.state.objects.erase(World.key(HOME+Vector2i.ONE))
	# A lone far corner (anchor gone) can never be dismantled for a refund, and is not a valid world.
	expect(valid(world.state.duplicate(true)),"fixture: the moved world is valid")
	world.state.objects.erase(World.key(DEST))
	var orphan_clay:=bag("clay")
	expect(not act("remove",DEST+Vector2i.ONE).ok and bag("clay")==orphan_clay,"an orphaned corner is never refunded")
	expect(not valid(world.state.duplicate(true)),"an orphaned corner is not a valid world")

func blueprint_scenario()->void:
	fresh()
	expect(act("build",HOME,KIND).ok,"fixture: stove built")
	var captured:=Design.capture(world.state,A,Rect2i(HOME,Vector2i(2,2)),"灶台",World.BUILD,World.NAMES)
	expect(captured.ok and captured.blueprint.pieces==[{"kind":KIND,"x":0,"y":0}],"capturing the stove records one piece")
	expect(not Design.capture(world.state,A,Rect2i(HOME,Vector2i(2,1)),"半個",World.BUILD,World.NAMES).ok,"an area cutting the stove in half is refused")
	expect(not Design.capture(world.state,A,Rect2i(HOME+Vector2i.ONE,Vector2i(1,1)),"一角",World.BUILD,World.NAMES).ok,"an area holding only one corner is refused")
	if not captured.ok:return
	fresh()
	put(A,MOVER)
	var wood:=bag("wood")
	var stone:=bag("stone")
	var clay:=bag("clay")
	var quote:=world.quote_blueprint(A,captured.blueprint,DEST,0)
	expect(quote.ok and int(quote.cost.stone)==20 and int(quote.cost.wood)==12 and int(quote.cost.clay)==5,"the quote prices one stove once: "+str(quote.get("message","")))
	var laid:=world.apply_blueprint(A,next_nonce(),captured.blueprint,DEST,0,str(quote.get("hash","")))
	expect(laid.ok and parts_ok(DEST) and all_blocked(cells_of(DEST),true),"apply builds four solid cells: "+str(laid.get("message","")))
	expect(bag("wood")==wood-12 and bag("stone")==stone-20 and bag("clay")==clay-5,"apply charges once")
	var undo:=world.undo_summary(A)
	if bool(undo.get("available",false)):
		expect(act(World.UNDO_ACTION,DEST,str(undo.get("id",""))).ok and empty(cells_of(DEST)) and bag("clay")==clay,"undoing the apply removes all four cells and refunds exactly")
	else:expect(false,"the blueprint apply is undoable")
	# A plan whose corner is taken is refused whole.
	world.state.objects[World.key(DEST+Vector2i.ONE)]={"type":"chest","owner":A,"items":{}}
	expect(not world.quote_blueprint(A,captured.blueprint,DEST,0).ok and bag("clay")==clay,"a plan with a taken corner is refused whole")
	world.state.objects.erase(World.key(DEST+Vector2i.ONE))

func save_scenario()->void:
	fresh()
	expect(act("build",HOME,KIND).ok,"fixture: stove built")
	expect(act("queue_cook",HOME,"soup").ok,"fixture: soup queued")
	expect(world.save(),"the world saves with a running C12 job")
	var saved:=World.new()
	expect(saved.load_world(path) and not saved.recovered_from_backup,"the world reloads from its primary save")
	expect(parts_ok_in(saved,HOME) and all_blocked(cells_of(HOME),true,saved),"parts and collision survive a reload")
	# The queue stays on the anchor: it comes back whole, with its 30 s snapshot, and nowhere else.
	var job:Dictionary=obj_in(saved,HOME).get("cooking",{}).get("active",{})
	expect(not job.is_empty() and job.kind=="soup" and float(job.duration)==30.0 and int(job["yield"])==2 and job.ingredients=={"radish":2},"the running canonical job survives the reload with its 30 s snapshot")
	for tile:Vector2i in cells_of(HOME).slice(1):expect(not obj_in(saved,tile).has("cooking"),"corner %s holds no queue after the reload"%World.key(tile))
	# A loaded world has no live sessions: mark the donor present, as joining would, then step and claim.
	saved.active_tokens[A]=true
	put(A,STAND,saved)
	expect(saved.step(31.0,true),"the reloaded world steps")
	var reclaimed:=act("claim_cook",HOME+Vector2i.ONE,"",A,saved)
	expect(reclaimed.ok and bag("soup",A,saved)==2,"the reloaded dish is claimed from the far corner (+2 soup): "+str(reclaimed.get("message","")))
	var good:=world.state.duplicate(true)
	expect(valid(good),"the fixture validates")
	var ak:=World.key(HOME)
	var fk:=World.key(HOME+Vector2i.ONE)
	var dk:=World.key(HOME+Vector2i.DOWN)
	var cases:={}
	var lost:=good.duplicate(true);lost.objects.erase(fk);cases["a corner missing"]=lost
	var no_anchor:=good.duplicate(true);no_anchor.objects.erase(ak);cases["anchor missing"]=no_anchor
	var stranger:=good.duplicate(true);stranger.objects[dk].owner=B;cases["a corner owned by someone else"]=stranger
	var swapped:=good.duplicate(true);swapped.objects[ak][FIELD]=1;cases["anchor marked as a corner"]=swapped
	var big:=good.duplicate(true);big.objects[fk][FIELD]=4;cases["part out of range"]=big
	var text:=good.duplicate(true);text.objects[fk][FIELD]="3";cases["part is text"]=text
	var bare:=good.duplicate(true);bare.objects[dk].erase(FIELD);cases["a corner unmarked"]=bare
	var alien:=good.duplicate(true);alien.objects[World.key(Vector2i(44,38))]={"type":"chest","owner":A,"items":{},FIELD:0};cases["marker on a chest"]=alien
	var stocked:=good.duplicate(true);stocked.objects[fk].items={"wood":1};cases["a corner carrying items"]=stocked
	var corner_queue:=good.duplicate(true);corner_queue.objects[fk].cooking=World.COOKING_QUEUE.empty_state();cases["a corner carrying a queue"]=corner_queue
	var legacy_job:=good.duplicate(true);legacy_job.objects[ak].job={"kind":"soup","ready":99999.0,"owner":A};cases["a C12 stove carrying a legacy job"]=legacy_job
	for label:String in cases:expect(not valid(cases[label]),"the validator rejects: "+label)

## An old world: a legacy 小石灶 with a running legacy job, the old numbers, and saves.
func legacy_scenario()->void:
	fresh()
	var stove:=OLD
	expect(act("build",stove,"stove").ok and obj(stove).get("type")=="stove" and not obj(stove).has(FIELD),"the early stove still builds as one cell with no part field")
	expect(bag("stone")==300-15 and bag("wood")==500-12 and bag("clay")==30,"the early stove costs 12 wood + 15 stone and no clay")
	expect(not world.state.objects.has(World.key(stove+Vector2i.ONE)),"and occupies no second cell")
	var radish:=bag("radish")
	var cooked:=act("cook",stove,"soup")
	expect(cooked.ok and obj(stove).has("job") and not obj(stove).has("cooking") and bag("radish")==radish-2,"the legacy job path is unchanged")
	expect(is_equal_approx(float(obj(stove).job.ready)-float(world.state.time),10.0),"the early stove still takes 10 s for soup")
	expect(not act("cook",stove,"rainbow_skewer").ok and not act("queue_cook",stove,"forest_mushroom_soup").ok,"the early stove cannot cook the C12-only dishes")
	expect(valid(world.state.duplicate(true)),"a world with a legacy running job validates")
	expect(world.save(),"it saves")
	var saved:=World.new()
	expect(saved.load_world(path) and obj_in(saved,stove).has("job"),"the legacy job survives a reload")
	saved.active_tokens[A]=true
	put(A,STAND,saved)
	expect(saved.step(11.0,true),"time passes")
	var claimed:=act("claim_cook",stove,"",A,saved)
	expect(claimed.ok and bag("soup",A,saved)==2,"the legacy dish is claimed with its original yield: "+str(claimed.get("message","")))
	# Queueing on the early stove still uses the OLD numbers (bread = 2 wheat, 15 s: the tutorial recipe).
	var queued:=act("queue_cook",stove,"bread",A,saved)
	expect(queued.ok and bag("wheat",A,saved)==8,"queueing bread on the early stove still costs 2 wheat")
	var active:Dictionary=obj_in(saved,stove).get("cooking",{}).get("active",{})
	expect(not active.is_empty() and float(active.duration)==15.0 and active.ingredients=={"wheat":2},"...and still takes 15 s (the tutorial recipe is not rewritten)")

## Q04: donate the 2x2 stove through the real actions and keep it alive across a reload.
func q04_scenario()->void:
	var w:=World.new()
	var kitchen_path:=path+".q04"
	w.save_path=kitchen_path
	setup_player(w,A,"灶A")
	setup_player(w,B,"灶B")
	open_island(w,[A,B])
	var table:=Community.table_cell(w.state)
	expect(table==Vector2i(39,30) and (PUB-table).length_squared()<=64,"fixture: the shared table is at (39,30) and the stove site is within 8 tiles")
	put(A,STAND,w)
	put(B,AWAY,w)
	expect(act("build",PUB,KIND,A,w).ok and parts_ok_in(w,PUB),"the 2x2 stove is built with the real build action")
	expect(act("build",SEAT1,"long_bench",A,w).ok,"the first long bench is built")
	expect(act("build",SEAT2,"long_bench",A,w).ok,"the second long bench is built")
	var good:="40,35|43,35"
	var far:=PUB+Vector2i.ONE
	expect(good==PK.seat_extra(SEAT1,SEAT2),"the seat list is in canonical order")
	expect(PK.candidate_stoves(w.state,A)==["41,33"],"the donation list offers the stove once (anchor only): "+str(PK.candidate_stoves(w.state,A)))
	expect(PK.candidate_stoves(w.state,B).is_empty(),"another member is offered nothing")
	# Refusals first (B stands within reach, so only ownership can be the reason).
	put(B,BESIDE,w)
	var theft:=act("kitchen_register",far,good,B,w)
	expect(not theft.ok and str(theft.message).contains("自己蓋的") and PK.stage(w.state)=="register","a friend cannot donate someone else's stove: "+str(theft.get("message","")))
	w.state.players[A].inventory.radish=2
	put(A,STAND,w)
	expect(act("queue_cook",far,"soup",A,w).ok,"fixture: the stove is busy")
	expect(not act("kitchen_register",far,good,A,w).ok and PK.stage(w.state)=="register","a stove with queued work cannot be donated")
	expect(w.step(31.0,true),"fixture: the canonical 30 s pass")
	expect(not act("kitchen_register",far,good,A,w).ok and PK.stage(w.state)=="register","an unclaimed dish also blocks the donation")
	expect(act("claim_cook",PUB,"",A,w).ok and bag("soup",A,w)==2,"fixture: the dish is claimed (+2 soup)")
	w.state.players[A].inventory["soup"]=0
	# Register through the FAR corner.
	var rid:="kitchen-stove-register"
	var registered:Dictionary=w.act(A,rid,"kitchen_register",far,good)
	expect(registered.ok,"registering through the far corner works: "+str(registered.get("message","")))
	expect(w.act(A,rid,"kitchen_register",far,good)==registered,"a replayed registration returns the stored receipt")
	var data:Dictionary=w.state.public_kitchen
	expect(data.stove=="41,33" and data.seats==["40,35","43,35"] and data.opened==false,"the kitchen records the anchor and the two seats")
	expect(PK.shape_ok(data) and PK.registered(w.state),"the stored kitchen shape is valid")
	var sites:=PK.site_cells(w.state)
	expect(sites.size()==6 and sites.slice(0,3)==[PUB,SEAT1,SEAT2] and sites.slice(3)==[PUB+Vector2i.RIGHT,PUB+Vector2i.DOWN,PUB+Vector2i.ONE],"site cells: stove, two seats, then the three other stove corners: "+str(sites))
	for tile in cells_of(PUB):expect(w.protected(tile) and PK.is_site_cell(w.state,tile),"every stove corner is permanently protected: "+World.key(tile))
	# Donated footprint: nobody (not even the donor) can move / remove / undo any corner. MOVER reaches DEST,
	# so the lock itself is the only reason for each refusal.
	put(A,MOVER,w)
	for tile in cells_of(PUB):
		var shove:=act("move_object",tile,World.key(DEST),A,w)
		expect(not shove.ok and shove.message==PK.MSG_LOCKED,"the donor cannot move corner %s: %s"%[World.key(tile),str(shove.get("message",""))])
		expect(not act("remove",tile,"",A,w).ok,"the donor cannot remove corner "+World.key(tile))
	expect(parts_ok_in(w,PUB),"all four corners are still there")
	expect(not bool(w.undo_summary(A).get("available",false)) or not act(World.UNDO_ACTION,PUB,str(w.undo_summary(A).get("id",""))).ok,"the donor's own build can no longer be undone")
	expect(parts_ok_in(w,PUB),"...and the stove survived the attempt")
	# Anyone may cook and claim; the shared kitchen counts the real meals.
	put(B,BESIDE,w)
	w.state.players[B].inventory["radish"]=2
	expect(act("queue_cook",far,"soup",B,w).ok,"a friend queues soup on the donated stove through the far corner")
	expect(w.step(31.0,true),"time passes")
	put(A,STAND,w)
	expect(act("claim_cook",PUB+Vector2i.DOWN,"",A,w).ok and bag("soup",A,w)==2,"the donor claims the friend's dish (+2 soup, from a third corner)")
	expect(not act("claim_cook",PUB,"",A,w).ok and bag("soup",A,w)==2,"nothing is claimed twice")
	# Contribute: 4 soup, 2 bread, 2 salad through the real action, from a corner.
	w.state.players[A].inventory["soup"]=4
	w.state.players[A].inventory["bread"]=2
	w.state.players[A].inventory["salad"]=2
	var given:=act("kitchen_contribute",far,"",A,w)
	expect(given.ok and w.state.public_kitchen.opened==true and bag("soup",A,w)==0 and bag("bread",A,w)==0 and bag("salad",A,w)==0,"contributing through a corner opens the kitchen and takes exactly the meals: "+str(given.get("message","")))
	expect(PK.stage(w.state)=="open" and PK.events(w.state).size()==3,"the kitchen is open and all three story pages are unlocked")
	expect(w.save(),"the opened kitchen saves")
	var again:=World.new()
	expect(again.load_world(kitchen_path) and not again.recovered_from_backup,"the opened kitchen reloads")
	expect(again.state.public_kitchen==w.state.public_kitchen and parts_ok_in(again,PUB),"public_kitchen and all four corners reload exactly")
	expect(PK.site_cells(again.state).size()==6 and again.protected(far),"the reloaded footprint is still protected")
	expect(valid(again.state.duplicate(true)),"the reloaded world validates")
	put(B,BESIDE,again)
	again.state.players[B].inventory["radish"]=2
	expect(act("queue_cook",far,"soup",B,again).ok,"the reloaded donated stove still cooks")
	# A corrupted kitchen is rejected: stove corner missing, anchor replaced by a plain chest.
	var broken:=again.state.duplicate(true)
	broken.objects.erase(World.key(far))
	expect(not valid(broken),"a donated 2x2 stove with a missing corner is not a valid world")
	var swapped:=again.state.duplicate(true)
	swapped.objects[World.key(PUB)]={"type":"chest","owner":A,"items":{}}
	expect(not valid(swapped),"a donated stove replaced by another object is not a valid world")
	for suffix in ["",".bak",".tmp",".staged",".writer-lock"]:
		if FileAccess.file_exists(kitchen_path+suffix):DirAccess.remove_absolute(kitchen_path+suffix)

## A kitchen donated with the early stove (a pre-C12 save) still loads, protects and cooks the old way.
func old_kitchen_scenario()->void:
	var w:=World.new()
	var old_path:=path+".old"
	w.save_path=old_path
	setup_player(w,A,"舊灶")
	open_island(w,[A])
	w.state.players[A].inventory["soup"]=2
	w.state.players[A].inventory["bread"]=1
	put(A,STAND,w)
	var built:=act("build",PUB,"stove",A,w)
	expect(built.ok and act("build",SEAT1,"long_bench",A,w).ok and act("build",SEAT2,"long_bench",A,w).ok,"fixture: an early stove and two benches: "+str(built.get("message","")))
	var registered:=act("kitchen_register",PUB,"40,35|43,35",A,w)
	expect(registered.ok and w.state.public_kitchen.stove=="41,33","the early stove is still donated by the same action: "+str(registered.get("message","")))
	expect(PK.site_cells(w.state).size()==3 and w.protected(PUB) and not w.protected(PUB+Vector2i.ONE),"a 1x1 donation still protects exactly three cells")
	w.state.players[A].inventory["radish"]=2
	expect(act("cook",PUB,"soup",A,w).ok and obj_in(w,PUB).has("job"),"the donated early stove still uses the legacy job")
	expect(w.save(),"it saves")
	var back:=World.new()
	expect(back.load_world(old_path) and back.state.public_kitchen==w.state.public_kitchen and obj_in(back,PUB).has("job"),"the old-style kitchen reloads with its job")
	expect(valid(back.state.duplicate(true)),"and validates")
	for suffix in ["",".bak",".tmp",".staged",".writer-lock"]:
		if FileAccess.file_exists(old_path+suffix):DirAccess.remove_absolute(old_path+suffix)

func run()->void:
	path="user://kitchen-stove-%d.json"%Time.get_ticks_usec()
	world=World.new()
	world.save_path=path
	setup_player(world,A,"灶主")
	setup_player(world,B,"旅客")
	open_island(world,[A,B])
	contract_scenario()
	geometry_scenario()
	build_scenario()
	interaction_scenario()
	eating_scenario()
	refund_move_undo_scenario()
	blueprint_scenario()
	save_scenario()
	legacy_scenario()
	q04_scenario()
	old_kitchen_scenario()
	finish()
