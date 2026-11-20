extends SceneTree
## C12 D05 森林菇湯：阿榆「林間的濕氣」常駐委託，走真正的 World.act 路徑。
##
## Fixtures are explicitly NOT normal play: inventories, coins, positions and the repaired-board
## flag are written directly. Every world saves into one unique random directory under the OS TEMP
## folder that is deleted afterwards; real player saves are never touched.
const World=preload("res://scripts/world.gd")
const FM=preload("res://scripts/forest_mushroom_commission.gd")
const KitchenStove=preload("res://scripts/kitchen_stove.gd")
const REGIONS=preload("res://scripts/regions.gd")

const A:="tok-forest-alice"
const B:="tok-forest-bob"
const HOME:=REGIONS.HOME

var checks:=0
var failures:=0
var serial:=0
var dir:=""

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var base:=OS.get_environment("TEMP")
	if base.is_empty():base=OS.get_environment("TMPDIR")
	if base.is_empty():base=OS.get_user_data_dir()
	dir=base.path_join("forest-mushroom-world-"+Crypto.new().generate_random_bytes(8).hex_encode())
	expect(not DirAccess.dir_exists_absolute(dir) and DirAccess.make_dir_recursive_absolute(dir)==OK,"isolated TEMP directory created")
	test_catalog_matches_game()
	test_pure_source()
	test_locked_until_board()
	test_full_commission()
	test_forest_rules()
	test_gate_cannot_be_skipped()
	test_real_stove_gate()
	test_failures_do_not_mutate()
	test_coin_cap_and_forged_input()
	test_save_roundtrip_and_schema()
	cleanup()
	print("FOREST_MUSHROOM_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

func cleanup() -> void:
	_remove_tree(dir)

func _remove_tree(path:String) -> void:
	var root_path:=dir.replace("\\","/").simplify_path()
	var target:=path.replace("\\","/").simplify_path()
	if not root_path.is_absolute_path() or (target!=root_path and not target.begins_with(root_path+"/")):
		expect(false,"Cleanup target escaped owned temporary directory")
		return
	if not DirAccess.dir_exists_absolute(path):return
	for sub in DirAccess.get_directories_at(path):_remove_tree(path.path_join(sub))
	for f in DirAccess.get_files_at(path):DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)

# ---------------------------------------------------------------- fixtures --

func new_world(board:=true):
	var w=World.new()
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	serial+=1
	w.save_path=dir.path_join("world-%d.json"%serial)
	w.state.board=board
	for t in [A,B]:
		w.state.players[t].inventory={"wood":5}
		w.state.players[t].coins=10
	return w

func supply(w,token:String,star:int,herb:int) -> void:
	var inv:Dictionary=w.state.players[token].inventory
	inv.star_mushroom=star
	inv.chime_herb=herb

func pose(w,token:String,at:Vector2) -> void:
	for t in w.state.players:
		var person:Dictionary=w.state.players[t]
		var spot:=at if t==token else World.SPAWN
		person.x=spot.x;person.y=spot.y

func aru_cell(w) -> Vector2i:
	var spot:Array=World.bond_place(w.state,FM.RESIDENT)
	return spot[1]

func beside(cell:Vector2i) -> Vector2:
	return Vector2(cell)+Vector2(1.5,0.5)

## One real World.act call. The player is first placed beside `cell` unless `at` is given.
func act(w,token:String,cell:Vector2i,extra:String,at:=Vector2(-1,-1)) -> Dictionary:
	serial+=1
	pose(w,token,beside(cell) if at.x<0 else at)
	return w.act(token,"fm-%d"%serial,FM.ACTION,cell,extra)

func find_tree(w,far:bool) -> Vector2i:
	for y in range(6,53):
		for x in range(5,73):
			var c:=Vector2i(x,y)
			if not w.is_land(c) or w.state.forest.has(World.key(c)):continue
			if str(w.resource(c))!="tree":continue
			if FM.forest_cell(c)==far:return c
	return Vector2i(-1,-1)

func find_open_far(w) -> Vector2i:
	for y in range(6,53):
		for x in range(5,73):
			var c:=Vector2i(x,y)
			if FM.forest_cell(c) and w.is_land(c) and not w.water(c) and not w.protected(c) and str(w.resource(c))=="":return c
	return Vector2i(-1,-1)

func stage(w,token:String) -> int:
	return FM.stage(w.state.players[token])

func snap(w) -> String:
	return var_to_str(w.state)

# ------------------------------------------------------------------- tests --

func test_catalog_matches_game() -> void:
	var dish:Dictionary=KitchenStove.dish(FM.DISH)
	expect(not dish.is_empty() and dish.dish=="D05" and dish.id=="forest_mushroom_soup","D05 is the existing forest_mushroom_soup row")
	expect(dish.ingredients==FM.NEEDS,"commission asks exactly the dish's own ingredients (no drift)")
	expect(World.RECIPES.has(FM.DISH) and World.NAMES.has(FM.DISH),"dish id exists in World.RECIPES / NAMES")
	for item:String in FM.NEEDS:
		expect(World.NAMES.get(item)==FM.ITEM_NAMES[item],"display name matches world "+item)
	expect(World.RESIDENT_BOND.RESIDENTS.has(FM.RESIDENT) and World.Village.NPCS.has(FM.RESIDENT),"阿榆 is an existing resident")
	expect(FM.BOARD==Vector2i(40,29) and FM.REGION==REGIONS.HOME,"board cell and home region match the game")
	expect(KitchenStove.EXCLUSIVE.has(FM.DISH),"D05 stays a C12-stove-only dish")
	var value:=0
	for item:String in FM.NEEDS:value+=int(World.CROPS[item].price)*int(FM.NEEDS[item])
	expect(FM.REWARD_COINS>0 and FM.REWARD_COINS<value,"reward %d is below the vendor value %d of the inputs (no arbitrage)"%[FM.REWARD_COINS,value])
	expect(not FM.NEEDS.has("star_mushroom_seed") and World.CROPS.star_mushroom.name==FM.ITEM_NAMES.star_mushroom,"inputs are crops, not seeds")
	expect(World.crop_terrain_problem("star_mushroom",Vector2i(20,20),"mine_5")=="" and World.crop_terrain_problem("star_mushroom",Vector2i(20,20),HOME)!="","star_mushroom only grows on the B5 bed")
	for key in ["ask","survey","after_survey","thanks"]:
		for banned in ["史實","歷史上","年建","真實人物","貓空","竹林"]:
			expect(not str(FM.LINES[key]).contains(banned),"no history claim / bamboo confusion in "+key)

func test_pure_source() -> void:
	var src:=FileAccess.get_file_as_string("res://scripts/forest_mushroom_commission.gd")
	expect(not src.is_empty(),"source readable")
	for banned in ["FileAccess","DirAccess","HTTPRequest","OS.","preload(","load(","Time.","randi","randf","print("]:
		expect(not src.contains(banned),"module stays pure: "+banned)

func test_locked_until_board() -> void:
	var w=new_world(false)
	var inventory_before:=var_to_str(w.state.players[A].inventory)
	var r:Dictionary=act(w,A,aru_cell(w),FM.ACCEPT)
	expect(not r.ok and r.message==FM.LOCKED_TEXT,"accept refused while the bulletin board is unrepaired")
	var tree:=find_tree(w,true)
	expect(tree.x>=0,"fixture: a natural far tree exists")
	expect(not act(w,A,tree,FM.SURVEY).ok,"survey refused while the board is unrepaired")
	expect(not act(w,A,aru_cell(w),FM.DELIVER).ok,"deliver refused while the board is unrepaired")
	expect(not w.state.players[A].has(FM.KEY),"no record written")
	expect(var_to_str(w.state.players[A].inventory)==inventory_before and int(w.state.players[A].coins)==10,"nothing granted or taken")
	var view:Dictionary=FM.view(w.state,w.state.players[A])
	expect(not view.open and view.next=="" and view.text==FM.LOCKED_TEXT,"view says why it is locked")

func test_full_commission() -> void:
	var w=new_world()
	supply(w,A,2,1)
	var orders_before:=var_to_str(w.state.players[A].get("orders",{}))
	var aru:=aru_cell(w)
	var tree:=find_tree(w,true)
	expect(FM.view(w.state,w.state.players[A]).next==FM.ACCEPT,"next action is accept")
	# Nothing can be skipped.
	expect(not act(w,A,tree,FM.SURVEY).ok and stage(w,A)==0,"cannot survey before accepting")
	expect(not act(w,A,aru,FM.DELIVER).ok and stage(w,A)==0,"cannot deliver before accepting")
	# Accept: a story line, no items, no coins.
	var inv_before:=var_to_str(w.state.players[A].inventory)
	var accept:Dictionary=act(w,A,aru,FM.ACCEPT)
	expect(accept.ok and stage(w,A)==FM.STAGE_ACCEPTED,"accept at 阿榆 writes stage 1")
	expect(var_to_str(w.state.players[A].inventory)==inv_before and int(w.state.players[A].coins)==10,"accept gives nothing")
	expect(not act(w,A,aru,FM.ACCEPT).ok,"accept cannot repeat")
	expect(not act(w,A,aru,FM.DELIVER).ok and stage(w,A)==1,"cannot deliver before looking at the forest")
	expect(FM.view(w.state,w.state.players[A]).next==FM.SURVEY,"next action is survey")
	# Forest excursion at a real natural tree far from the board.
	var survey:Dictionary=act(w,A,tree,FM.SURVEY)
	expect(survey.ok and stage(w,A)==FM.STAGE_SURVEYED,"survey at a far natural tree writes stage 2")
	expect(str(survey.message).contains("菌床"),"survey story points at the mushroom bed")
	expect(var_to_str(w.state.players[A].inventory)==inv_before and int(w.state.players[A].coins)==10,"survey gives nothing")
	expect(not act(w,A,tree,FM.SURVEY).ok,"survey cannot repeat")
	expect(not FM.done(w.state.players[A]),"recipe is still locked before delivery")
	# Deliver at 阿榆 consumes exactly the inputs and pays only coins.
	var done:Dictionary=act(w,A,aru,FM.DELIVER)
	expect(done.ok and stage(w,A)==FM.STAGE_DONE and FM.done(w.state.players[A]),"deliver unlocks the personal recipe")
	var inv:Dictionary=w.state.players[A].inventory
	expect(int(inv.star_mushroom)==0 and int(inv.chime_herb)==0 and int(inv.wood)==5,"exactly 2 星夜菇 + 1 風鈴香草 consumed")
	expect(int(w.state.players[A].coins)==10+FM.REWARD_COINS,"reward is only coins")
	expect(not inv.has(FM.DISH) and not inv.has("star_mushroom_seed") and not inv.has("chime_herb_seed"),"no dish, seed or ingredient handed out")
	expect(not act(w,A,aru,FM.DELIVER).ok,"deliver cannot repeat")
	supply(w,A,2,1)
	var coins:=int(w.state.players[A].coins)
	expect(not act(w,A,aru,FM.DELIVER).ok and int(w.state.players[A].coins)==coins and int(w.state.players[A].inventory.star_mushroom)==2,"replay pays nothing and keeps items")
	# Personal, and independent of the generic order slots.
	expect(stage(w,B)==0 and not FM.done(w.state.players[B]) and int(w.state.players[B].coins)==10,"other players are untouched")
	expect(var_to_str(w.state.players[A].get("orders",{}))==orders_before,"order slots untouched")
	var view:Dictionary=FM.view(w.state,w.state.players[A])
	expect(view.done and view.next=="" and view.stage==3,"view reports the finished commission")

func test_forest_rules() -> void:
	var w=new_world()
	var aru:=aru_cell(w)
	expect(act(w,A,aru,FM.ACCEPT).ok,"fixture: accepted")
	var far:=find_tree(w,true)
	var near:=find_tree(w,false)
	var open:=find_open_far(w)
	expect(far.x>=0 and near.x>=0 and open.x>=0,"fixtures: far tree, near tree, open far cell")
	expect(not act(w,A,near,FM.SURVEY).ok and stage(w,A)==1,"a tree near the village is not the forest")
	expect(not act(w,A,open,FM.SURVEY).ok and stage(w,A)==1,"an empty cell is not a tree")
	expect(not act(w,A,far,FM.SURVEY,Vector2(far)+Vector2(8.5,0.5)).ok and stage(w,A)==1,"too far from the tree")
	# A tree the player planted is not a natural tree.
	w.state.forest[World.key(open)]={"growth":0.0,"mature":true,"owner":A}
	expect(str(w.resource(open))=="tree","fixture: planted mature tree reads as a tree")
	expect(not act(w,A,open,FM.SURVEY).ok and stage(w,A)==1,"a planted tree does not count")
	w.state.forest.erase(World.key(open))
	# A felled natural tree does not count either.
	w.state.removed[World.key(far)]=true
	expect(not act(w,A,far,FM.SURVEY).ok and stage(w,A)==1,"a felled tree does not count")
	w.state.removed.erase(World.key(far))
	# Other regions are refused even beside a tree (region is the server's, not the client's).
	w.state.players[A].region="lanyang"
	expect(not act(w,A,far,FM.SURVEY).ok and stage(w,A)==1,"survey only counts in the home forest")
	w.state.players[A].region=HOME
	expect(act(w,A,far,FM.SURVEY).ok and stage(w,A)==2,"a natural far tree works")
	# Bamboo / tea regions never advance it.
	var w2=new_world()
	expect(act(w2,A,aru_cell(w2),FM.ACCEPT).ok,"fixture 2: accepted")
	w2.state.players[A].region="maokong"
	expect(not act(w2,A,Vector2i(20,20),FM.SURVEY).ok and stage(w2,A)==1,"貓空 does not stand in for the forest")

func test_gate_cannot_be_skipped() -> void:
	var w=new_world()
	supply(w,A,5,5)
	var aru:=aru_cell(w)
	expect(not act(w,A,aru,FM.DELIVER).ok and not FM.done(w.state.players[A]),"holding the items alone never unlocks the recipe")
	expect(act(w,A,aru,FM.ACCEPT).ok,"accepted")
	expect(not act(w,A,aru,FM.DELIVER).ok and stage(w,A)==1,"still needs the forest visit")
	var tree:=find_tree(w,true)
	expect(act(w,A,tree,FM.SURVEY).ok,"surveyed")
	# Wrong place for the hand-in.
	expect(not act(w,A,Vector2i(20,20),FM.DELIVER).ok and stage(w,A)==2,"must hand in at 阿榆's cell")
	expect(not act(w,A,aru,FM.DELIVER,Vector2(aru)+Vector2(9.5,0.5)).ok and stage(w,A)==2,"must stand beside 阿榆")

## Real new 2x2 stove (built through World.act): D05 is refused before the commission is done, then queued and
## claimed after the real accept / survey / deliver. Refusals change nothing.
func test_real_stove_gate() -> void:
	var w=new_world()
	var stove:=Vector2i(41,33)
	var stand:=Vector2(42.5,35.5)
	for x in range(38,51):
		for y in range(32,41):w.state.removed[World.key(Vector2i(x,y))]=true
	var inv:Dictionary=w.state.players[A].inventory
	inv.merge({"wood":500,"stone":300,"fiber":100,"clay":30,"bamboo":20,"cotton_cloth":6},true)
	supply(w,A,2,1)
	serial+=1
	pose(w,A,stand)
	var built:Dictionary=w.act(A,"fm-stove-%d"%serial,"build",stove,KitchenStove.KIND)
	expect(built.ok and w.state.objects.get(World.key(stove),{}).get("type","")==KitchenStove.KIND,"fixture: the real C12 stove is built: "+str(built.get("message","")))
	var star:=int(inv.star_mushroom)
	var herb:=int(inv.chime_herb)
	var before:=var_to_str(inv)
	serial+=1
	pose(w,A,stand)
	var refused:Dictionary=w.act(A,"fm-q-%d"%serial,"queue_cook",stove,FM.DISH)
	expect(not refused.ok and refused.message==FM.COOKING_LOCK,"gate: D05 refused on the new stove before the commission: "+str(refused.get("message","")))
	expect(var_to_str(inv)==before and int(inv.star_mushroom)==star and int(inv.chime_herb)==herb and not w.state.objects[World.key(stove)].has("cooking"),"gate: refusal leaves bag and queue untouched")
	serial+=1
	pose(w,A,stand)
	expect(not w.act(A,"fm-c-%d"%serial,"cook",stove,FM.DISH).ok and not w.state.objects[World.key(stove)].has("cooking"),"gate: the older cook verb is refused too")
	expect(w.stove_dish_locked(w.state.players[A],KitchenStove.KIND,FM.DISH),"host predicate: locked before the commission")
	# The real commission.
	var aru:=aru_cell(w)
	expect(act(w,A,aru,FM.ACCEPT).ok and act(w,A,find_tree(w,true),FM.SURVEY).ok and act(w,A,aru,FM.DELIVER).ok and FM.done(w.state.players[A]),"fixture: commission finished through the real actions")
	expect(not w.stove_dish_locked(w.state.players[A],KitchenStove.KIND,FM.DISH),"host predicate: open after the commission")
	supply(w,A,2,1)
	serial+=1
	pose(w,A,stand)
	var queued:Dictionary=w.act(A,"fm-q-%d"%serial,"queue_cook",stove,FM.DISH)
	expect(queued.ok and int(inv.star_mushroom)==0 and int(inv.chime_herb)==0,"queue: after the commission D05 takes exactly 2 star mushrooms + 1 chime herb: "+str(queued.get("message","")))
	var job:Dictionary=w.state.objects[World.key(stove)].get("cooking",{}).get("active",{})
	expect(not job.is_empty() and job.kind==FM.DISH and int(job["yield"])==2,"queue: the active job is D05 with yield 2")
	expect(w.step(61.0,true),"stove time passes")
	serial+=1
	pose(w,A,stand)
	var claimed:Dictionary=w.act(A,"fm-cl-%d"%serial,"claim_cook",stove)
	expect(claimed.ok and int(inv.get(FM.DISH,0))==2,"claim: 2 portions of forest_mushroom_soup: "+str(claimed.get("message","")))
	expect(w.stove_dish_locked(w.state.players[B],KitchenStove.KIND,FM.DISH),"gate is per player: B is still locked")

func test_failures_do_not_mutate() -> void:
	var w=new_world()
	var aru:=aru_cell(w)
	var tree:=find_tree(w,true)
	expect(act(w,A,aru,FM.ACCEPT).ok and act(w,A,tree,FM.SURVEY).ok,"fixture: surveyed")
	for held in [[0,0],[1,0],[2,0],[0,1],[1,1]]:
		supply(w,A,int(held[0]),int(held[1]))
		var r:Dictionary=act(w,A,aru,FM.DELIVER)
		expect(not r.ok and stage(w,A)==2,"short inputs %s refused"%str(held))
		expect(int(w.state.players[A].coins)==10 and int(w.state.players[A].inventory.star_mushroom)==int(held[0]) and int(w.state.players[A].inventory.chime_herb)==int(held[1]),"short inputs %s consume nothing"%str(held))
	var view:Dictionary=FM.view(w.state,w.state.players[A])
	expect(view.next==FM.DELIVER and not view.missing.is_empty() and str(view.text).contains("菌床"),"view lists what is missing and where the bed is")

func test_coin_cap_and_forged_input() -> void:
	var w=new_world()
	var aru:=aru_cell(w)
	var tree:=find_tree(w,true)
	expect(act(w,A,aru,FM.ACCEPT).ok and act(w,A,tree,FM.SURVEY).ok,"fixture: surveyed")
	supply(w,A,2,1)
	w.state.players[A].coins=FM.LIMIT-FM.REWARD_COINS+1
	expect(not act(w,A,aru,FM.DELIVER).ok and stage(w,A)==2 and int(w.state.players[A].inventory.star_mushroom)==2,"coin cap refuses and keeps the items")
	w.state.players[A].coins=FM.LIMIT-FM.REWARD_COINS
	expect(act(w,A,aru,FM.DELIVER).ok and int(w.state.players[A].coins)==FM.LIMIT,"exactly at the cap is allowed")
	# Forged requests.
	var w2=new_world()
	for extra in ["","ACCEPT","accept ","survey:1","complete","../deliver"]:
		expect(not act(w2,A,aru_cell(w2),extra).ok,"unknown extra refused: '%s'"%extra)
	expect(not w2.state.players[A].has(FM.KEY),"forged extras write nothing")
	expect(not w2.act("tok-nobody","fm-x",FM.ACTION,aru_cell(w2),FM.ACCEPT).ok,"unknown token refused")
	expect(FM.count_of(-5)==-1 and FM.count_of("many")==-1 and FM.count_of(1.5)==-1,"count_of rejects malformed numbers")

func test_save_roundtrip_and_schema() -> void:
	var w=new_world()
	var aru:=aru_cell(w)
	var tree:=find_tree(w,true)
	supply(w,A,2,1)
	expect(act(w,A,aru,FM.ACCEPT).ok and act(w,A,tree,FM.SURVEY).ok and act(w,A,aru,FM.DELIVER).ok,"fixture: finished")
	expect(w.step(1.0,true),"world saved")
	var path:String=w.save_path
	var loaded=World.new()
	expect(loaded.load_world(path),"reload passes real SaveSchema validation")
	expect(FM.done(loaded.state.players[A]) and not FM.done(loaded.state.players[B]),"personal unlock survives a reload")
	# A hand-edited save with an impossible record is refused by the schema.
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	expect(parsed is Dictionary,"save parses")
	if not parsed is Dictionary:return
	for bad in [9,0,-1,"3",true,2.5]:
		var copy:Dictionary=(parsed as Dictionary).duplicate(true)
		copy.players[A][FM.KEY]=bad
		var bad_path:=dir.path_join("bad-%d.json"%serial)
		serial+=1
		var file:=FileAccess.open(bad_path,FileAccess.WRITE)
		file.store_string(JSON.stringify(copy))
		file.close()
		expect(not World.new().load_world(bad_path),"schema refuses record %s"%str(bad))
	var no_board:Dictionary=(parsed as Dictionary).duplicate(true)
	no_board.board=false
	var board_path:=dir.path_join("no-board-%d.json"%serial)
	serial+=1
	var board_file:=FileAccess.open(board_path,FileAccess.WRITE)
	board_file.store_string(JSON.stringify(no_board))
	board_file.close()
	expect(not World.new().load_world(board_path),"schema refuses a commission record without a repaired board")
