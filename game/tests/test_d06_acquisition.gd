extends SceneTree
## D06 香煎溪魚 location acquisition (河灣橋與海岸步道). Pure World, works with --headless.
##
##   godot --headless --path game --script res://tests/test_d06_acquisition.gd
##
## Pinned contract:
##   - 銀線溪魚淺灘 (S.SHOAL_RECT) opens with the Q05 bridge, always pays minnow, is disjoint from the
##     河灣橋釣點 (redfish by day, loach by night, unchanged) and from the fishing-meet waters; before the bridge
##     opens and on every other tile standard fishing is unchanged.
##   - The repaired 星砂海岸步道 offers a 北門鹽田 salt parcel: SALT_PARCEL_AMOUNT sea_salt, once per player per
##     world day, SALT_PARCEL_LIFETIME deliveries per player in total. Supplies are per player, duplicate request
##     ids never pay twice, and the fields survive a save/reload and are validated.
##   - The C12 stove D06 row is untouched (this change adds acquisition only).

const World=preload("res://scripts/world.gd")
const S=World.STONE_WORKSHOP
const Coast=World.WANGAN_COAST
const Collections=preload("res://scripts/collections.gd")
const SHOAL_TILE:=Vector2i(55,24)
const SHOAL_BANK:=Vector2(54.5,23.5)
const POOL_TILE:=Vector2i(55,28)
const POOL_BANK:=Vector2(54.5,28.5)
const MEET_TILE:=Vector2i(55,35)
const FAR_TILE:=Vector2i(55,20)

var world:World
var owner:="d06-owner"
var guest:="d06-guest"
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
	return world.act(owner if who.is_empty() else who,"d06-%d"%serial,verb,tile,extra)

func valid(state:Dictionary)->bool:
	return bool(World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME))

func centre(tile:Vector2i)->Vector2:
	return Vector2(tile)+Vector2(0.5,0.5)

func put(token:String,at:Vector2)->void:
	world.state.players[token].x=at.x
	world.state.players[token].y=at.y

func bag(item:String,who:="")->int:
	return int(world.state.players[owner if who.is_empty() else who].inventory.get(item,0))

func cast_and_reel(bank:Vector2,tile:Vector2i,time:float)->Dictionary:
	world.state.time=time
	world.state.players[owner].erase("fishing")
	put(owner,bank)
	var cast:=act("fish_start",tile)
	if not cast.ok:return cast
	world.state.time+=4.0
	return act("fish_catch",tile)

func finish()->void:
	for suffix in ["",".bak",".tmp",".staged",".writer-lock",".corrupt"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("D06_ACQUISITION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func shoal_rules_scenario()->void:
	world.state.board=false
	expect(not S.bridge_open(world.state) and not S.shoal_spot(world.state,SHOAL_TILE),"before Q05 the shoal is not a special spot")
	world.state.board=true
	world.state.erase(S.PROJECT_KEY)
	expect(S.shoal_spot(world.state,SHOAL_TILE) and S.shoal_spot(world.state,Vector2i(56,25)) and S.shoal_spot(world.state,Vector2i(55,23)),"the shoal opens with the bridge")
	var overlap:=false
	for tile:Vector2i in [Vector2i(55,23),Vector2i(56,23),Vector2i(55,24),Vector2i(56,24),Vector2i(55,25),Vector2i(56,25)]:
		if S.fishing_spot(world.state,tile) or not world.water(tile):overlap=true
	expect(not overlap,"every shoal tile is river water and none belongs to the 河灣橋釣點")
	expect(not S.shoal_spot(world.state,POOL_TILE) and not S.shoal_spot(world.state,MEET_TILE) and not S.shoal_spot(world.state,FAR_TILE) and not S.shoal_spot(world.state,Vector2i(55,30)),"the pool, the meet waters, the far river and the deck are not the shoal")
	expect(S.fishing_spot(world.state,POOL_TILE),"the 河灣橋釣點 is still where it was")
	# Catch table.
	expect(Collections.fishing_result("home","spring",0,{},720.0,S.SHOAL_SPOT).id=="minnow" and Collections.fishing_result("home","spring",3,{},1300.0,S.SHOAL_SPOT).id=="minnow","the shoal pays minnow day and night")
	expect(Collections.fishing_result("home","spring",0,{},720.0,S.FISHING_SPOT).id=="redfish" and Collections.fishing_result("home","spring",1,{},1300.0,S.FISHING_SPOT).id=="loach","the bridge pool still pays redfish by day and loach by night")
	for total in 8:
		expect(Collections.fishing_result("home","spring",total,{},720.0,"coast").id==Collections.FRESHWATER_FISH[total%4],"standard river rotation is unchanged (total %d)"%total)
	expect(Collections.fishing_result("home","spring",0,{},720.0,Coast.FISHING_SPOT).id=="sardine","the Wangan south shore is unchanged")

func shoal_fishing_scenario()->void:
	world.state.board=false
	world.state.erase(S.PROJECT_KEY)
	world.state.players[owner].inventory={}
	world.state.players[owner].fish_caught=0
	expect(world.can_stand(SHOAL_BANK) and not world.water(Vector2i(54,23)),"the shoal's west bank (54,23) is dry and standable")
	var before:=cast_and_reel(SHOAL_BANK,SHOAL_TILE,720.0)
	expect(before.ok and bag("carp")==1 and bag("minnow")==0,"before the bridge the shoal tile is plain river (rotation starts at carp): "+str(before.get("message","")))
	world.state.board=true
	var day:=cast_and_reel(SHOAL_BANK,SHOAL_TILE,720.0)
	expect(day.ok and bag("minnow")==1,"by day the open shoal lands 銀線溪魚 in the bag: "+str(day.get("message","")))
	var night:=cast_and_reel(SHOAL_BANK,SHOAL_TILE,1300.0)
	expect(night.ok and bag("minnow")==2,"at night the shoal still lands 銀線溪魚: "+str(night.get("message","")))
	var redfish:=cast_and_reel(POOL_BANK,POOL_TILE,720.0)
	expect(redfish.ok and bag("redfish")==1 and bag("minnow")==2,"the bridge pool still lands redfish by day: "+str(redfish.get("message","")))
	var loach:=cast_and_reel(POOL_BANK,POOL_TILE,1300.0)
	expect(loach.ok and bag("loach")==1 and bag("minnow")==2,"the bridge pool still lands loach at night: "+str(loach.get("message","")))
	var count_before:=bag("carp")+bag("minnow")+bag("redfish")+bag("loach")
	var far:=cast_and_reel(Vector2(54.5,20.5),FAR_TILE,720.0)
	var count_after:=bag("carp")+bag("minnow")+bag("redfish")+bag("loach")
	expect(far.ok and count_after==count_before+1,"standard river fishing elsewhere still works: "+str(far.get("message","")))

func parcel_scenario()->void:
	var cell:=Coast.SALT_PARCEL
	expect(cell==Vector2i(35,54) and Coast.star_boardwalk(cell) and World.land(cell) and not world.water(cell) and world.can_stand(centre(cell)),"the parcel sits on the walkable start of the star boardwalk")
	expect(cell!=Coast.STAR_SAND and cell!=Coast.STAR_REPAIR and cell!=Coast.DOCK_ORDERS and cell!=Coast.SHELL_CELL,"the parcel cell is distinct from the other coast points")
	world.state.wangan_star_walk=false
	world.state.players[owner].inventory={}
	put(owner,centre(cell))
	var early:=act(Coast.SALT_PARCEL_POINT,cell)
	expect(not early.ok and bag("sea_salt")==0 and not world.state.players[owner].has(Coast.SALT_PARCEL_DAY_KEY),"nothing is delivered before the walk is repaired: "+str(early.get("message","")))
	expect(not world.protected(cell),"before the repair the parcel cell is ordinary ground")
	# Real repair.
	world.state.players[owner].inventory={"plank":8,"fiber":4}
	put(owner,centre(Coast.STAR_REPAIR))
	var repair:=act(Coast.STAR_REPAIR_POINT,Coast.STAR_REPAIR)
	expect(repair.ok and world.state.wangan_star_walk==true,"the real repair opens the walk: "+str(repair.get("message","")))
	expect(world.protected(cell),"after the repair the parcel cell is protected")
	expect(Coast.SALT_PARCEL in [Vector2i(35,54)] and World.essential_cell_reason(world.state,"home",cell)!="","the parcel cell is an essential cell (cannot be built over by pavilions)")
	# Claims.
	put(owner,centre(cell))
	var first:=act(Coast.SALT_PARCEL_POINT,cell)
	expect(first.ok and bag("sea_salt")==Coast.SALT_PARCEL_AMOUNT,"the first claim brings the limited salt: "+str(first.get("message","")))
	expect(String(first.message).contains("北門鹽田"),"the delivery is tied narratively to 北門鹽田")
	var again:=act(Coast.SALT_PARCEL_POINT,cell)
	expect(not again.ok and bag("sea_salt")==Coast.SALT_PARCEL_AMOUNT,"a second claim the same day pays nothing: "+str(again.get("message","")))
	var wait:=World.WEATHER.DAY_SECONDS*0.45
	world.state.time+=wait
	var still:=act(Coast.SALT_PARCEL_POINT,cell)
	expect(not still.ok and bag("sea_salt")==Coast.SALT_PARCEL_AMOUNT,"spending the salt or waiting inside the same world day never refills it")
	# Replay of a request id returns the stored receipt without paying again.
	var replay_id:="d06-replay"
	var wrong_cell:=world.act(owner,replay_id,Coast.SALT_PARCEL_POINT,Vector2i(36,54),"")
	expect(not wrong_cell.ok and bag("sea_salt")==Coast.SALT_PARCEL_AMOUNT,"the wrong cell is refused")
	expect(not act(Coast.SALT_PARCEL_POINT,cell,"extra").ok and bag("sea_salt")==Coast.SALT_PARCEL_AMOUNT,"a non-empty extra is refused")
	# Per-player supply.
	world.state.players[guest].inventory={}
	put(guest,centre(cell))
	var guest_claim:=act(Coast.SALT_PARCEL_POINT,cell,"",guest)
	expect(guest_claim.ok and bag("sea_salt","d06-guest")==Coast.SALT_PARCEL_AMOUNT and bag("sea_salt")==Coast.SALT_PARCEL_AMOUNT,"the second player has their own parcel and the first is untouched: "+str(guest_claim.get("message","")))
	var guest_duplicate:=world.act(guest,"d06-guest-dup",Coast.SALT_PARCEL_POINT,cell,"")
	var guest_replay:=world.act(guest,"d06-guest-dup",Coast.SALT_PARCEL_POINT,cell,"")
	expect(guest_replay==guest_duplicate and bag("sea_salt","d06-guest")==Coast.SALT_PARCEL_AMOUNT,"a replayed request id never pays twice")
	expect(valid(world.state),"a state with one claim each validates")
	# Reload keeps the day gate.
	expect(world.save(),"the world saves")
	var reloaded:=World.new()
	reloaded.save_path=path
	expect(reloaded.load_world(path),"the world loads")
	var owner_after:Dictionary=reloaded.state.players[owner]
	expect(int(owner_after.get(Coast.SALT_PARCEL_TOTAL_KEY,0))==1 and int(owner_after.get(Coast.SALT_PARCEL_DAY_KEY,0))==1,"the per-player claim record survives a reload")
	expect(not reloaded.act(owner,"d06-reload",Coast.SALT_PARCEL_POINT,cell,"").ok,"after a reload the same day is still claimed")
	# Next days, then the lifetime cap.
	for day_step in range(1,Coast.SALT_PARCEL_LIFETIME):
		world.state.time=World.WEATHER.DAY_SECONDS*day_step+720.0
		put(owner,centre(cell))
		expect(act(Coast.SALT_PARCEL_POINT,cell).ok,"day %d offers the parcel again"%(day_step+1))
	expect(bag("sea_salt")==Coast.SALT_PARCEL_AMOUNT*Coast.SALT_PARCEL_LIFETIME,"the limited supply adds up to exactly amount x lifetime")
	world.state.time=World.WEATHER.DAY_SECONDS*Coast.SALT_PARCEL_LIFETIME+720.0
	var capped:=act(Coast.SALT_PARCEL_POINT,cell)
	expect(not capped.ok and bag("sea_salt")==Coast.SALT_PARCEL_AMOUNT*Coast.SALT_PARCEL_LIFETIME and String(capped.message).contains("北門鹽田"),"after the lifetime cap the player is pointed back to 北門鹽田: "+str(capped.get("message","")))
	# Bag cap.
	world.state.players[guest].inventory={"sea_salt":1000000000-1}
	world.state.time=World.WEATHER.DAY_SECONDS*5+720.0
	put(guest,centre(cell))
	expect(not act(Coast.SALT_PARCEL_POINT,cell,"",guest).ok and bag("sea_salt","d06-guest")==1000000000-1,"a nearly full bag refuses instead of overflowing")
	expect(valid(world.state),"the capped state still validates")

func validator_scenario()->void:
	var good:=world.state.duplicate(true)
	expect(valid(good),"baseline state validates")
	var cases:={}
	var day_only:=good.duplicate(true);day_only.players[owner].erase(Coast.SALT_PARCEL_TOTAL_KEY);cases["day without total"]=day_only
	var total_only:=good.duplicate(true);total_only.players[owner].erase(Coast.SALT_PARCEL_DAY_KEY);cases["total without day"]=total_only
	var future:=good.duplicate(true);future.players[owner][Coast.SALT_PARCEL_DAY_KEY]=9999;cases["a day in the future"]=future
	var over:=good.duplicate(true);over.players[owner][Coast.SALT_PARCEL_TOTAL_KEY]=Coast.SALT_PARCEL_LIFETIME+1;cases["over the lifetime cap"]=over
	var zero:=good.duplicate(true);zero.players[owner][Coast.SALT_PARCEL_TOTAL_KEY]=0;cases["zero total"]=zero
	var fractional:=good.duplicate(true);fractional.players[owner][Coast.SALT_PARCEL_TOTAL_KEY]=1.5;cases["fractional total"]=fractional
	var text:=good.duplicate(true);text.players[owner][Coast.SALT_PARCEL_DAY_KEY]="1";cases["text day"]=text
	for label:String in cases:expect(not valid(cases[label]),"the validator rejects: "+label)

func contract_scenario()->void:
	var d06:Dictionary={}
	for dish:Dictionary in World.KITCHEN_STOVE.DISHES:
		if dish.id=="salt_grilled_fish":d06=dish
	expect(d06.get("dish")=="D06" and d06.ingredients=={"minnow":1,"sea_salt":1} and float(d06.time)==60.0 and int(d06.restore)==40,"the C12 D06 stove row is untouched")
	expect(World.NAMES.has("sea_salt") and World.NAMES.has("minnow") and not World.CROPS.has("sea_salt"),"sea_salt keeps its id and stays out of the crop price table")
	expect(not World.OTHER_SALES.has("sea_salt"),"sea_salt is still never sellable")

func run()->void:
	path="user://d06-acquisition-%d.json"%Time.get_ticks_usec()
	world=World.new()
	world.save_path=path
	world.add_player(owner,"取魚者")
	world.add_player(guest,"旅客")
	world.state.time=720.0
	contract_scenario()
	shoal_rules_scenario()
	shoal_fishing_scenario()
	parcel_scenario()
	validator_scenario()
	finish()
