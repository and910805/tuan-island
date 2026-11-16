extends SceneTree
## Bakery (pumpkin / flour mill / pumpkin pie) through the REAL World.act /
## World.step / World.save / World.load_world path.
## Contract: work/claude-agents/bakery_core.txt
##   CROPS.pumpkin 琥珀南瓜 time 270 price 150 seed_price 70 yield 1
##   CRAFT.mill_kit 麵粉磨坊 plank 8 stone 16 copper_joint 4 -> 1
##   BUILD.mill consumes mill_kit 1; craft AND build gated on public_kitchen.opened
##   INDUSTRY.PROCESS.flour station mill, wheat 2 -> 1 in 60 s
##   RECIPES.pumpkin_pie pumpkin 1 flour 1 egg 1 -> 4 in 120 s, sells 80 each
##   bread/feed unchanged, flour is not a meal, mill buffers wheat in input_wheat,
##   conveyors filter wheat/flour, save schema 24, protocol 43, release 0.48-dev.
##
## The core may still be landing: every missing piece is a FAILED check, never a
## skip. Catalog lookups use .get() so a missing key never aborts the run.
## Only contract values are asserted; message wording is only required non-empty.
##
## FIXTURE, NOT NORMAL PLAY (disclosed; each write is labelled where it happens):
##  * backpack stock (wood/stone/fiber/plank/copper_joint/wheat/conveyor_kit,
##    farm tools + charcoal, coins, prepared picnic/kitchen meals) is written
##    directly into inventories;
##  * player A's aru story stage is set to 2 (Village gate for long_bench);
##  * players are teleported (pose) within reach before every action;
##  * one stored queue record has its ingredients rewritten to emulate a
##    historical snapshot (exact-refund check);
##  * schema checks load mutated copies of real save files written by this run.
## EARNED (real actions on top of that stock): the public kitchen is opened by
## real donate / picnic / build / kitchen_register / kitchen_contribute (never by
## writing opened=true); the mill kit is crafted at a real bench and the mill is
## really built; the pie chain buys seeds, hoes, sows, waters, grows (World.step),
## harvests wheat + pumpkin, cooks feed, feeds the hen, collects the egg, mills
## flour, bakes the pie and sells it. Later worlds load copies of the real,
## schema-valid save of that opened-kitchen world (the "template").
## World time moves only through World.step(dt, true). Every world saves into one
## fresh random directory under TEMP; cleanup removes only that directory.
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const Collections=preload("res://scripts/collections.gd")
const Community=preload("res://scripts/community.gd")
const Sources=preload("res://scripts/material_sources.gd")
const Supply=preload("res://scripts/material_supply.gd")
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const REGIONS=preload("res://scripts/regions.gd")

const LABEL:="bakery-world/seed-20261114"
const A:="tok-alice-SECRET"
const B:="tok-bob-SECRET"
const HOME:=REGIONS.HOME
const TOL:=0.000001
const RELEASE_PATH:="res://release.json"
# ---- contract values (bakery_core.txt) ----
const SAVE_VERSION:=26
const PROTOCOL:=45
const RELEASE_VERSION:="0.50-dev"
const CUTOFFS:={"BLUEPRINT_HISTORY_VERSION":19,"COOKING_QUEUE_VERSION":20,"PROCESSING_QUEUE_VERSION":21,"MATERIAL_SOURCE_VERSION":22,"PUBLIC_KITCHEN_VERSION":23}
const PUMPKIN_NAME:="琥珀南瓜"
const PUMPKIN_TIME:=270.0
const PUMPKIN_PRICE:=150
const PUMPKIN_SEED_PRICE:=70
const MILL_NAME:="麵粉磨坊"
const MILL_KIT_COST:={"plank":8,"stone":16,"copper_joint":4}
const FLOUR_COST:={"wheat":2}
const FLOUR_TIME:=60.0
const FLOUR_YIELD:=1
const PIE_COST:={"pumpkin":1,"flour":1,"egg":1}
const PIE_TIME:=120.0
const PIE_YIELD:=4
const PIE_PRICE:=80
const NEW_ITEMS:=["pumpkin","pumpkin_seed","flour","pumpkin_pie","mill_kit"]
# ---- pre-bakery snapshots that must stay exactly equal ----
const BREAD:={"name":"小麥麵包","ingredients":{"wheat":2},"time":15.0,"yield":1}
const FEED:={"name":"混合飼料","ingredients":{"wheat":1,"fiber":2},"time":5.0,"yield":4}
const PLANK:={"station":"sawmill","ingredients":{"wood":4},"time":12.0,"yield":2}
const CHARCOAL:={"station":"charcoal_kiln","ingredients":{"wood":4},"time":16.0,"yield":2}
const BREAD_PRICE:=48
const WHEAT:={"name":"星點小麥","time":120.0,"price":19,"seed_price":18,"yield":2}
# ---- public kitchen geometry (same site as test_public_kitchen_world.gd) ----
const BOARD:=Vector2i(40,29)
const STOVE:=Vector2i(42,34)
const SEAT1:=Vector2i(40,34)
const SEAT2:=Vector2i(44,34)
const SEATS:="40,34|44,34"
const STALL:=Vector2i(43,29)
const HEN:=Vector2i(45,34)
const PLAZA:=Vector2(40.0,32.0)
const PARK:=Vector2(36.5,36.5)

class FakeClock extends RefCounted:
	var utc:float=1800000000.0
	var ticks:int=7000000
	func now_utc() -> float:return utc
	func now_ticks() -> int:return ticks

var checks:=0
var failures:=0
var serial:=0
var dir:=""
var used_sites:Array=[]
var template_text:=""
var bench_cell:=Vector2i(-1,-1)
var chest_cell:=Vector2i(-1,-1)
var mill_cell:=Vector2i(-1,-1)

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var base:=OS.get_environment("TEMP")
	if base.is_empty():base=OS.get_environment("TMPDIR")
	if base.is_empty():base=OS.get_user_data_dir()
	dir=base.path_join("bakery-world-"+Crypto.new().generate_random_bytes(8).hex_encode())
	if DirAccess.dir_exists_absolute(dir):
		expect(false,"refuse to adopt an existing test directory")
		finish()
		return
	expect(DirAccess.make_dir_recursive_absolute(dir)==OK,"isolated TEMP directory created")
	print("BAKERY_WORLD fixture=%s"%LABEL)
	test_catalog()
	test_gate_and_open()
	test_farm_tools()
	test_earned_pie_chain()
	test_tea_pudding()
	test_star_rice_ball()
	test_strawberry_toast_gift()
	test_handcraft_rope()
	test_jam_pot()
	test_mill_queue()
	test_legacy_sawmill_unchanged()
	test_mill_material_box()
	test_mill_buffers_and_auto()
	test_mill_conveyor_chain()
	test_mill_rejects_wood_then_buffers_wheat()
	test_save_reload_and_schema()
	test_legacy_saves()
	_remove_tree(dir)
	expect(not DirAccess.dir_exists_absolute(dir),"isolated TEMP directory removed")
	finish()

func finish() -> void:
	print("BAKERY_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

func _remove_tree(path:String) -> void:
	var root_path:=dir.replace("\\","/").simplify_path()
	var target:=path.replace("\\","/").simplify_path()
	if dir.is_empty() or not root_path.is_absolute_path() or (target!=root_path and not target.begins_with(root_path+"/")):
		expect(false,"cleanup target escaped the owned temporary directory")
		return
	if not DirAccess.dir_exists_absolute(path):return
	for sub in DirAccess.get_directories_at(path):_remove_tree(path.path_join(sub))
	for f in DirAccess.get_files_at(path):DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)

func write_text(path:String,text:String) -> void:
	var f:=FileAccess.open(path,FileAccess.WRITE)
	expect(f!=null,"fixture file writable: "+path.get_file())
	if f==null:return
	f.store_string(text)
	f.close()

# ---------------------------------------------------------------- fixtures --

func attach(w) -> void:
	var clock:=FakeClock.new()
	w.undo_clock_utc=Callable(clock,"now_utc")
	w.undo_clock_ticks=Callable(clock,"now_ticks")

func new_world():
	var w=World.new()
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	serial+=1
	w.save_path=dir.path_join("world-%d.json"%serial)
	attach(w)
	return w

## Copy of the real opened-kitchen save, loaded through real SaveSchema validation.
func from_template():
	serial+=1
	var path:=dir.path_join("world-%d.json"%serial)
	write_text(path,template_text)
	var w=World.new()
	var loaded:bool=w.load_world(path)
	expect(loaded and not template_text.is_empty(),"template copy %d loads through SaveSchema"%serial)
	if not w.state.players.has(A):w.add_player(A,"Alice")
	if not w.state.players.has(B):w.add_player(B,"Bob")
	w.save_path=path
	attach(w)
	return w

## FIXTURE: direct backpack writes (never normal play).
func stock(w,token:String,items:Dictionary) -> void:
	var bag:Dictionary=w.state.players[token].inventory
	for item in items:bag[item]=int(items[item])

func set_coins(w,token:String,amount:int) -> void:
	# FIXTURE: direct coin write.
	w.state.players[token].coins=amount

func coins(w,token:String=A) -> int:
	return int(w.state.players[token].get("coins",0))

func held(w,item:String,token:String=A) -> int:
	return int(w.state.players[token].inventory.get(item,0))

func inv(w,token:String=A) -> Dictionary:
	var out:={}
	var src:Dictionary=w.state.players[token].inventory
	for item in src:
		if int(src[item])!=0:out[str(item)]=int(src[item])
	return out

func diff(before:Dictionary,after:Dictionary) -> Dictionary:
	var out:={}
	var keys:=before.keys()
	for k in after:
		if not k in keys:keys.append(k)
	for k in keys:
		var d:=int(after.get(k,0))-int(before.get(k,0))
		if d!=0:out[str(k)]=d
	return out

func ints(value) -> Dictionary:
	var out:={}
	if value is Dictionary:
		for k in value:out[str(k)]=int(value[k])
	return out

func materials(recipe) -> Dictionary:
	var out:={}
	if recipe is Dictionary:
		for k in recipe:
			if str(k)!="name":out[str(k)]=int(recipe[k])
	return out

func close(a:float,b:float) -> bool:
	return absf(a-b)<=TOL

func cell_free(w,c:Vector2i) -> bool:
	if not w.is_land(c) or w.water(c) or w.protected(c) or w.resource(c)!="":return false
	var k:=World.key(c)
	for field in ["objects","ground","roofs","crops","forest"]:
		if w.state[field].has(k):return false
	return true

## Naturally empty HOME rectangle (no state writes), away from the plaza/kitchen
## and from every site used earlier in this run.
func find_area(w,size:Vector2i,label:String) -> Vector2i:
	for oy in range(4,54):
		for ox in range(4,72):
			var centre:=Vector2(ox,oy)+Vector2(size)*0.5
			if centre.distance_to(PLAZA)<12.0:continue
			var far:=true
			for u in used_sites:
				if centre.distance_to(u)<7.0:
					far=false
					break
			if not far:continue
			var good:=true
			for y in range(oy,oy+size.y):
				for x in range(ox,ox+size.x):
					if not cell_free(w,Vector2i(x,y)):
						good=false
						break
				if not good:break
			if good:
				used_sites.append(centre)
				return Vector2i(ox,oy)
	expect(false,"found a naturally empty site for "+label)
	return Vector2i(-1,-1)

func near(p:Vector2i) -> Vector2:
	return Vector2(p)+Vector2(0.5,1.6)

func reserved() -> Array:
	var out:Array=[STOVE,SEAT1,SEAT2,BOARD,STALL,HEN]
	out.append_array(Community.CANDIDATES)
	return out

## Closest standable HOME position 1..2.9 tiles from `target` (kitchen actions).
func stand_near(w,target:Vector2i) -> Vector2:
	var best:=Vector2.ZERO
	var best_d:=INF
	var skip:=reserved()
	var centre:=Vector2(target)+Vector2(0.5,0.5)
	for dy in range(-3,4):
		for dx in range(-3,4):
			var c:=target+Vector2i(dx,dy)
			if c in skip:continue
			var pos:=Vector2(c)+Vector2(0.5,0.5)
			var d:=pos.distance_to(centre)
			if d<0.99 or d>2.9 or not w.can_stand(pos):continue
			if d<best_d:
				best=pos
				best_d=d
	expect(best_d<INF,"fixture: standable spot near "+World.key(target))
	return best

## FIXTURE: teleport `token` to `at`, everyone else waits at PARK.
func pose(w,token:String,at:Vector2) -> void:
	for t in w.state.players:
		var person:Dictionary=w.state.players[t]
		var spot:=at if t==token else PARK
		person.x=spot.x
		person.y=spot.y

func leak_free(value,label:String) -> void:
	var text:=var_to_str(value)
	expect(not text.contains("SECRET") and not text.contains("tok-"),label+": never leaks tokens")

func do(w,token:String,action:String,p:Vector2i,extra:String="",at=null,rid:String="") -> Dictionary:
	pose(w,token,near(p) if at==null else at)
	serial+=1
	if rid=="":rid="bk-%d"%serial
	var r:Dictionary=w.act(token,rid,action,p,extra)
	leak_free(r,"result %s"%action)
	return r

func must(w,token:String,action:String,p:Vector2i,extra:String,label:String,at=null,rid:String="") -> Dictionary:
	var r:=do(w,token,action,p,extra,at,rid)
	expect(r.get("ok",false)==true,label+": "+str(r.get("message","")))
	return r

## Rejected: ok=false with a reason and the whole world state unchanged.
func refuse(w,token:String,action:String,p:Vector2i,extra:String,label:String,at=null) -> Dictionary:
	pose(w,token,near(p) if at==null else at)
	var snap:=var_to_str(w.state)
	serial+=1
	var r:Dictionary=w.act(token,"refuse-%d"%serial,action,p,extra)
	leak_free(r,label)
	expect(r.get("ok",true)==false and str(r.get("message","")).length()>0,label+": rejected with a reason, got "+str(r))
	expect(var_to_str(w.state)==snap,label+": world state unchanged")
	return r

func dev(w,p:Vector2i) -> Dictionary:
	var v=w.state.objects.get(World.key(p),{})
	return v if v is Dictionary else {}

func q(w,p:Vector2i) -> Dictionary:
	var c=dev(w,p).get("processing")
	return c if c is Dictionary else {}

func ids_of(list) -> Array:
	var out:=[]
	if list is Array:
		for entry in list:
			if entry is Dictionary:out.append(str(entry.get("id","")))
	return out

func all_ids(c:Dictionary) -> Array:
	var out:=[]
	if c.is_empty():return out
	var active=c.get("active",{})
	if active is Dictionary and not active.is_empty():out.append(str(active.get("id","")))
	return out+ids_of(c.get("waiting",[]))+ids_of(c.get("ready",[]))

func active_id(c:Dictionary) -> String:
	var active=c.get("active",{})
	return str(active.get("id","")) if active is Dictionary else ""

func ready_n(c:Dictionary) -> int:
	var r=c.get("ready",[])
	return (r as Array).size() if r is Array else 0

func empty_queue(d:Dictionary) -> bool:
	if not d.has("processing"):return true
	var c=d.get("processing")
	return c is Dictionary and all_ids(c).is_empty()

func buffer_empty(d:Dictionary) -> bool:
	var items=d.get("items",{})
	if not items is Dictionary:return false
	for v in items.values():
		if int(v)!=0:return false
	return true

func hex32(value) -> bool:
	return value is String and World._is_lower_hex(value,32)

func kitchen(w) -> Dictionary:
	var v=w.state.get("public_kitchen")
	return v if v is Dictionary else {}

func kitchen_open(w) -> bool:
	return kitchen(w).get("opened")==true

func crop(w,c:Vector2i) -> Dictionary:
	var v=w.state.crops.get(World.key(c),{})
	return v if v is Dictionary else {}

func meals_seen(w,token:String=A) -> Dictionary:
	var col=w.state.players[token].get("collection",{})
	var m=col.get("meals",{}) if col is Dictionary else {}
	return m if m is Dictionary else {}

func queue_ids(w,p:Vector2i,recipe:String,n:int,label:String,token:String=A) -> Array:
	var out:=[]
	for i in n:
		var before:=all_ids(q(w,p))
		must(w,token,"queue_processing",p,recipe,"%s %d"%[label,i])
		var added:=all_ids(q(w,p)).filter(func(id):return not before.has(id))
		expect(added.size()==1 and hex32(added[0] if added.size()==1 else null),"%s %d: exactly one new 32-hex job"%[label,i])
		if added.size()==1:out.append(added[0])
	return out

## Client-equivalent sourced wire: MaterialSupply split + MaterialSources digest.
func quote(w,action:String,station:Vector2i,recipe:String,chest:Vector2i,box:String) -> Dictionary:
	var kind:=str(dev(w,station).get("type",""))
	var def:Dictionary={}
	if action=="craft":
		var raw=World.CRAFT.get(recipe,{})
		if raw is Dictionary:def=raw
	else:
		var raw=World.processing_recipes(kind).get(recipe,{})
		if raw is Dictionary:def=raw
	var items:Dictionary=dev(w,chest).get("items",{})
	var plan:Dictionary=Supply.plan(def.get("ingredients",{}),w.state.players[A].inventory,items)
	var alloc:={"from_backpack":plan.get("from_backpack",{}),"from_chest":plan.get("from_chest",{})}
	var d:String=Sources.digest(action,kind,World.key(station),recipe,def,World.key(chest),box,alloc)
	return {"plan":plan,"extra":Sources.encode(recipe,World.key(chest),box,d)}

func blueprint_quote(w,origin:Vector2i) -> Dictionary:
	pose(w,A,near(origin))
	var before:=var_to_str(w.state)
	var raw:={"version":1,"name":"Mill","width":1,"height":1,"pieces":[{"kind":"mill","x":0,"y":0}]}
	var result=w.quote_blueprint(A,raw,origin,0)
	expect(var_to_str(w.state)==before,"blueprint quote is read-only")
	return result if result is Dictionary else {}

## FIXTURE stock + REAL craft at the template bench + REAL build.
func craft_and_build_mill(w,at:Vector2i,label:String) -> void:
	# FIXTURE: mill kit materials in the backpack.
	stock(w,A,{"plank":held(w,"plank")+8,"stone":held(w,"stone")+16,"copper_joint":held(w,"copper_joint")+4})
	must(w,A,"craft",bench_cell,"mill_kit",label+": craft mill_kit at the bench")
	must(w,A,"build",at,"mill",label+": build mill")
	expect(dev(w,at).get("type")=="mill" and dev(w,at).get("owner")==A,label+": mill owned by builder")

# ------------------------------------------------------------------- tests --

func test_catalog() -> void:
	var probe=World.new()
	expect(int(probe.state.version)==int(Schema.VERSION),"fresh world follows SaveSchema.VERSION")
	expect(int(Schema.VERSION)==SAVE_VERSION,"public save schema version is 26, got %d"%int(Schema.VERSION))
	var cut_ok:=Schema.BLUEPRINT_HISTORY_VERSION==19 and Schema.COOKING_QUEUE_VERSION==20 and Schema.PROCESSING_QUEUE_VERSION==21 and Schema.MATERIAL_SOURCE_VERSION==22 and Schema.PUBLIC_KITCHEN_VERSION==23
	expect(cut_ok,"historical feature cutoffs 19/20/21/22/23 preserved "+str(CUTOFFS))
	expect(int(Session.PROTOCOL)==PROTOCOL,"network protocol is 45, got %d"%int(Session.PROTOCOL))
	var parser:=JSON.new()
	var rel_ok:=parser.parse(FileAccess.get_file_as_string(RELEASE_PATH))==OK and parser.data is Dictionary
	var rel:Dictionary=parser.data if rel_ok else {}
	expect(str(rel.get("version",""))==RELEASE_VERSION and int(rel.get("protocol",-1))==PROTOCOL,"release.json 0.50-dev / protocol 45: "+str(rel.get("version"))+" / "+str(rel.get("protocol")))
	expect(int(rel.get("protocol",-1))==int(Session.PROTOCOL),"release protocol equals Session.PROTOCOL")
	# pumpkin crop
	var pumpkin=World.CROPS.get("pumpkin",{})
	var pk:Dictionary=pumpkin if pumpkin is Dictionary else {}
	expect(str(pk.get("name",""))==PUMPKIN_NAME,"pumpkin name 琥珀南瓜")
	expect(close(float(pk.get("time",-1)),PUMPKIN_TIME) and int(pk.get("price",-1))==PUMPKIN_PRICE and int(pk.get("seed_price",-1))==PUMPKIN_SEED_PRICE and int(pk.get("yield",-1))==1,"pumpkin time 270, price 150, seed 70, yield 1: "+str(pk))
	expect(int(pk.get("cycles",1))==1,"pumpkin is a single-harvest crop")
	expect(World.CROPS.get("wheat")==WHEAT,"wheat crop unchanged")
	# mill kit + mill
	var kit=World.CRAFT.get("mill_kit",{})
	var kd:Dictionary=kit if kit is Dictionary else {}
	expect(str(kd.get("name",""))==MILL_NAME and ints(kd.get("ingredients",{}))==MILL_KIT_COST and int(kd.get("yield",-1))==1,"mill_kit 麵粉磨坊 plank8 stone16 copper_joint4 -> 1: "+str(kd))
	expect(materials(World.BUILD.get("mill",{}))=={"mill_kit":1},"BUILD.mill consumes exactly one mill_kit: "+str(World.BUILD.get("mill")))
	expect(str(World.BUILD.get("mill",{}).get("name",""))!="","BUILD.mill has a display name")
	# flour processing
	var flour=World.INDUSTRY.PROCESS.get("flour",{})
	var fl:Dictionary=flour if flour is Dictionary else {}
	expect(fl.get("station")=="mill" and ints(fl.get("ingredients",{}))==FLOUR_COST and int(fl.get("yield",-1))==FLOUR_YIELD and close(float(fl.get("time",-1)),FLOUR_TIME),"flour: mill, wheat 2 -> 1, 60 s: "+str(fl))
	expect(World.processing_recipes("mill").keys()==["flour","feed"],"mill offers flour and corn feed")
	expect(World.INDUSTRY.PROCESS.get("plank")==PLANK and World.INDUSTRY.PROCESS.get("charcoal")==CHARCOAL,"plank/charcoal processing unchanged")
	expect(not World.processing_recipes("sawmill").has("flour") and not World.processing_recipes("charcoal_kiln").has("flour"),"flour never offered on sawmill/kiln")
	# pie
	var pie=World.RECIPES.get("pumpkin_pie",{})
	var pd:Dictionary=pie if pie is Dictionary else {}
	expect(ints(pd.get("ingredients",{}))==PIE_COST and int(pd.get("yield",-1))==PIE_YIELD and close(float(pd.get("time",-1)),PIE_TIME),"pumpkin_pie pumpkin1 flour1 egg1 -> 4, 120 s: "+str(pd))
	expect(str(pd.get("name",""))!="","pumpkin_pie has a recipe name")
	expect(int(World.OTHER_SALES.get("pumpkin_pie",-1))==PIE_PRICE,"pumpkin_pie sells for 80 each")
	# unchanged progression
	expect(World.RECIPES.get("bread")==BREAD,"bread recipe unchanged: "+str(World.RECIPES.get("bread")))
	expect(World.RECIPES.get("feed")==FEED,"feed recipe unchanged: "+str(World.RECIPES.get("feed")))
	expect(int(World.OTHER_SALES.get("bread",-1))==BREAD_PRICE,"bread price unchanged")
	expect(not World.RECIPES.has("flour"),"flour is not a stove recipe (no bread/flour cycle)")
	# Historical recipes remain checked even as later chapters add recipes.
	for id in ["soup","bread","feed","salad","baked_potato","grilled_fish","carrot_soup"]:
		expect(World.RECIPES.has(id),"pre-bakery recipe %s preserved"%id)
		var ing=World.RECIPES.get(id,{}).get("ingredients",{})
		expect(ing is Dictionary and not ing.is_empty() and not ing.has("flour") and not ing.has("pumpkin"),"pre-bakery recipe %s does not need flour/pumpkin"%id)
	# names / classification / meals
	for id in NEW_ITEMS:expect(str(World.NAMES.get(id,"")).length()>0,"NAMES has "+id)
	expect(not Collections.is_meal("flour"),"flour is never classified as a meal")
	expect(Collections.is_meal("pumpkin_pie"),"pumpkin_pie is a meal")
	expect(Collections.is_meal("bread") and not Collections.is_meal("feed"),"bread/feed meal classification unchanged")
	expect(InventoryPanel.category_for("pumpkin")==InventoryPanel.category_for("wheat"),"pumpkin sorted with harvests")
	expect(InventoryPanel.category_for("pumpkin_seed")==InventoryPanel.category_for("wheat_seed"),"pumpkin_seed sorted with seeds")
	expect(InventoryPanel.category_for("flour")!=InventoryPanel.category_for("bread"),"flour not sorted with prepared meals")
	expect(InventoryPanel.category_for("mill_kit")==InventoryPanel.category_for("sawmill_kit"),"mill_kit sorted with the other station kits")

## Gate before opening (craft, sourced craft, build, blueprint), then a real
## public-kitchen opening, then the same routes succeed. Saved as the template.
func test_gate_and_open() -> void:
	var w=new_world()
	# FIXTURE: materials for bench, chest, kitchen site and mill kits.
	stock(w,A,{"wood":600,"stone":260,"fiber":120,"plank":40,"copper_joint":12})
	# FIXTURE: aru story stage 2 (Village gate for the kitchen's long benches).
	var stories=w.state.players[A].get("stories",{})
	stories["aru"]=maxi(2,int(stories.get("aru",0)))
	w.state.players[A]["stories"]=stories
	var o:=find_area(w,Vector2i(5,2),"gate site")
	if o.x<0:return
	bench_cell=o
	chest_cell=o+Vector2i(1,0)
	mill_cell=o+Vector2i(3,0)
	must(w,A,"build",bench_cell,"bench","gate: real bench build")
	must(w,A,"build",chest_cell,"chest","gate: real shared chest beside the bench")
	expect(not kitchen_open(w),"gate: kitchen starts unopened")
	refuse(w,A,"craft",bench_cell,"mill_kit","gate: mill_kit craft locked before the kitchen opens")
	var inv0:=inv(w)
	must(w,A,"craft",bench_cell,"sawmill_kit","gate: unrelated bench craft still works")
	expect(diff(inv0,inv(w))=={"wood":-8,"stone":-4,"sawmill_kit":1},"gate: sawmill_kit cost unchanged")
	for i in 4:must(w,A,"deposit",chest_cell,"stone","gate: deposit stone %d"%i)
	# FIXTURE: backpack stone trimmed so the chest must cover part of the mill kit.
	stock(w,A,{"stone":12})
	var prep:=must(w,A,"prepare_material_box",bench_cell,World.key(chest_cell),"gate: prepare the shared chest")
	var box:=str(prep.get("source_id",""))
	var sq:=quote(w,"craft",bench_cell,"mill_kit",chest_cell,box)
	expect(sq.plan.get("ok")==true and ints(sq.plan.get("from_chest",{}))=={"stone":4},"gate: quoted split takes 4 stone from the chest: "+str(sq.plan))
	refuse(w,A,"craft",bench_cell,sq.extra,"gate: sourced mill_kit craft locked before opening")
	# FIXTURE: one mill_kit in the backpack only to probe the build gate.
	stock(w,A,{"mill_kit":1})
	refuse(w,A,"build",mill_cell,"mill","gate: mill build locked before opening")
	var qb:=blueprint_quote(w,mill_cell)
	expect(qb.get("ok")!=true and str(qb.get("message","")).length()>0,"gate: blueprint with a mill quoted as blocked: "+str(qb.get("message","")))
	stock(w,A,{"mill_kit":0,"stone":200}) # FIXTURE: probe kit removed, stone restored.
	open_kitchen(w)
	expect(kitchen_open(w),"open: kitchen opened through real actions: "+str(kitchen(w)))
	inv0=inv(w)
	must(w,A,"craft",bench_cell,"mill_kit","open: craft mill_kit at the bench")
	expect(diff(inv0,inv(w))=={"plank":-8,"stone":-16,"copper_joint":-4,"mill_kit":1},"open: exact mill kit cost and yield: "+str(diff(inv0,inv(w))))
	stock(w,A,{"stone":12}) # FIXTURE: chest must cover 4 stone again.
	sq=quote(w,"craft",bench_cell,"mill_kit",chest_cell,box)
	var kits:=held(w,"mill_kit")
	var sr:=must(w,A,"craft",bench_cell,sq.extra,"open: sourced mill_kit craft")
	expect(ints(sr.get("from_chest",{}))=={"stone":4} and held(w,"mill_kit")==kits+1 and int(dev(w,chest_cell).get("items",{}).get("stone",0))==0 and held(w,"stone")==0,"open: sourced craft debits backpack 12 + chest 4 stone exactly")
	kits=held(w,"mill_kit")
	var builds0:=int(w.state.players[A].get("builds",0))
	must(w,A,"build",mill_cell,"mill","open: build the mill")
	var m:=dev(w,mill_cell)
	expect(m.get("type")=="mill" and m.get("owner")==A and held(w,"mill_kit")==kits-1,"open: mill placed, one kit consumed")
	expect(int(w.state.players[A].get("builds",0))==builds0+1,"open: build counted once")
	expect(m.has("input_wheat") and (m.get("input_wheat") is int or m.get("input_wheat") is float),"open: mill carries an input_wheat buffer")
	expect(int(m.get("input_wheat",-1))==0 and m.get("auto_enabled")==false and buffer_empty(m) and not m.has("job") and empty_queue(m),"open: fresh mill idle, empty buffers, auto off: "+str(m))
	expect(int(m.get("input_wood",0))==0,"open: mill holds no wood buffer")
	var qb2:=blueprint_quote(w,mill_cell+Vector2i(0,1))
	expect(qb2.get("ok")==true,"open: blueprint with a mill quotes after opening: "+str(qb2.get("message","")))
	expect(w.save(),"open: template saved")
	template_text=FileAccess.get_file_as_string(w.save_path)
	var parser:=JSON.new()
	expect(parser.parse(template_text)==OK and parser.data is Dictionary and parser.data.get("public_kitchen",{}).get("opened")==true,"open: saved template carries the opened kitchen")

func open_kitchen(w) -> void:
	must(w,A,"donate",BOARD,"","kitchen: board via real donate",stand_near(w,BOARD))
	# FIXTURE: prepared picnic meals (2 soup + 1 bread).
	stock(w,A,{"soup":2,"bread":1})
	must(w,A,"picnic",BOARD,"","kitchen: picnic via real act",stand_near(w,BOARD))
	for spec in [[STOVE,"stove"],[SEAT1,"long_bench"],[SEAT2,"long_bench"]]:
		must(w,A,"build",spec[0],spec[1],"kitchen: build "+str(spec[1]),stand_near(w,spec[0]))
	must(w,A,"kitchen_register",STOVE,SEATS,"kitchen: register stove + two seats",stand_near(w,STOVE))
	expect(kitchen(w).get("stove")==World.key(STOVE) and kitchen(w).get("opened")==false,"kitchen: registered but not yet opened")
	refuse(w,A,"craft",bench_cell,"mill_kit","gate: still locked while registered but unopened")
	stock(w,A,{"mill_kit":1}) # FIXTURE probe kit
	refuse(w,A,"build",mill_cell,"mill","gate: build still locked while registered but unopened")
	stock(w,A,{"mill_kit":0})
	# FIXTURE: prepared meals the kitchen asks members to donate (SaveSchema caps).
	var meals:={}
	for meal in Schema.KITCHEN_MEALS:meals[meal]=int(Schema.KITCHEN_MEALS[meal])
	stock(w,A,meals)
	must(w,A,"kitchen_contribute",STOVE,"","kitchen: contribute every outstanding meal",stand_near(w,STOVE))

func test_farm_tools() -> void:
	var w=from_template()
	# Begin on the sunny first morning of autumn for the exact watering checks.
	w.state.time = 2 * World.WEATHER.DAYS_PER_SEASON * World.WEATHER.DAY_SECONDS
	# FIXTURE: farm tools, charcoal and coins.
	stock(w,A,{"tiller":1,"seeder":1,"harvester":1,"charcoal":3})
	set_coins(w,A,1000)
	set_coins(w,B,PUMPKIN_SEED_PRICE-1)
	refuse(w,B,"buy",STALL,"pumpkin","farm: 69 coins cannot buy a pumpkin seed")
	var c0:=coins(w)
	for i in 9:must(w,A,"buy",STALL,"pumpkin","farm: buy pumpkin seed %d"%i)
	expect(coins(w)==c0-9*PUMPKIN_SEED_PRICE and held(w,"pumpkin_seed")==9,"farm: nine seeds cost 9 x 70")
	var o:=find_area(w,Vector2i(3,3),"tool farm")
	if o.x<0:return
	var centre:=o+Vector2i(1,1)
	var at:=Vector2(centre)+Vector2(0.5,0.5)
	var cells:=[]
	for y in 3:
		for x in 3:cells.append(o+Vector2i(x,y))
	must(w,A,"till_area",centre,"","farm: tiller prepares 3x3",at)
	must(w,A,"seed_area",centre,"pumpkin","farm: seeder sows pumpkin",at)
	var sown:=true
	for c in cells:
		var plot:=crop(w,c)
		if plot.get("kind")!="pumpkin" or float(plot.get("growth",-1))!=0.0 or int(plot.get("remaining",0))!=1 or plot.get("owner")!=A:sown=false
	expect(sown and held(w,"pumpkin_seed")==0 and held(w,"charcoal")==1,"farm: nine pumpkin plots, nine seeds and two charcoal spent")
	refuse(w,A,"harvest_area",centre,"","farm: nothing ripe to harvest",at)
	expect(w.step(30.0,true),"farm: dry step")
	expect(cells.all(func(c):return float(crop(w,c).get("growth",-1))==0.0),"farm: dry pumpkins do not grow")
	for c in cells:must(w,A,"water",c,"","farm: water %s"%World.key(c))
	expect(w.step(PUMPKIN_TIME-1.0,true),"farm: watered growth to 269 s")
	refuse(w,A,"harvest_area",centre,"","farm: 269 s pumpkins are not ripe",at)
	refuse(w,A,"harvest",o,"","farm: single plot not ripe at 269 s")
	expect(w.step(2.0,true),"farm: growth past 270 s")
	expect(cells.all(func(c):return close(float(crop(w,c).get("growth",-1)),PUMPKIN_TIME)),"farm: growth clamps at exactly 270")
	var p0:=held(w,"pumpkin")
	var h0:=int(w.state.players[A].get("harvests",0))
	must(w,A,"harvest_area",centre,"","farm: harvester reaps pumpkins",at)
	expect(held(w,"pumpkin")==p0+9 and int(w.state.players[A].get("harvests",0))==h0+9,"farm: yield 1 per plot (+9)")
	expect(cells.all(func(c):return crop(w,c).get("kind")=="" and crop(w,c).get("wet")==false),"farm: plots empty after the single harvest")
	expect(w.state.players[A].get("collection",{}).get("crops",{}).get("pumpkin")==true,"farm: pumpkin recorded in the crop collection")
	c0=coins(w)
	must(w,A,"sell",STALL,"pumpkin","farm: sell pumpkins")
	expect(coins(w)==c0+9*PUMPKIN_PRICE and held(w,"pumpkin")==0,"farm: nine pumpkins sell for 9 x 150")

## EARNED chain on the template: only coins (seed money) are written directly.
func test_earned_pie_chain() -> void:
	var w=from_template()
	w.state.time = 2 * World.WEATHER.DAYS_PER_SEASON * World.WEATHER.DAY_SECONDS
	set_coins(w,A,PUMPKIN_SEED_PRICE+2*int(WHEAT.seed_price)) # FIXTURE: exact seed money.
	for id in ["pumpkin","wheat","flour","egg","feed","pumpkin_pie"]:expect(held(w,id)==0,"chain: starts without "+id)
	must(w,A,"buy",STALL,"pumpkin","chain: buy pumpkin seed")
	for i in 2:must(w,A,"buy",STALL,"wheat","chain: buy wheat seed %d"%i)
	expect(coins(w)==0,"chain: all seed money spent")
	var o:=find_area(w,Vector2i(3,1),"chain plots")
	if o.x<0:return
	var pumpkin:=o
	var wheat:=[o+Vector2i(1,0),o+Vector2i(2,0)]
	for c in [pumpkin]+wheat:must(w,A,"hoe",c,"","chain: hoe "+World.key(c))
	must(w,A,"seed",pumpkin,"pumpkin","chain: sow pumpkin")
	for c in wheat:must(w,A,"seed",c,"wheat","chain: sow wheat")
	for c in [pumpkin]+wheat:must(w,A,"water",c,"","chain: water "+World.key(c))
	expect(w.step(float(WHEAT.time)+1.0,true),"chain: wheat ripens")
	for c in wheat:must(w,A,"harvest",c,"","chain: harvest wheat")
	expect(held(w,"wheat")==4,"chain: two wheat plots yield 4 wheat")
	refuse(w,A,"harvest",pumpkin,"","chain: pumpkin not ripe at 121 s")
	# flour on the template mill
	var cooked0:=int(w.state.players[A].get("cooked",0))
	must(w,A,"queue_processing",mill_cell,"flour","chain: mill wheat into flour")
	expect(held(w,"wheat")==2,"chain: milling takes exactly 2 wheat")
	expect(w.step(FLOUR_TIME-1.0,true),"chain: 59 s of milling")
	refuse(w,A,"claim_processing",mill_cell,"","chain: flour not ready at 59 s")
	expect(w.step(1.5,true),"chain: milling finishes")
	must(w,A,"claim_processing",mill_cell,"","chain: claim flour")
	expect(held(w,"flour")==FLOUR_YIELD,"chain: one flour")
	expect(int(w.state.players[A].get("cooked",0))==cooked0 and not meals_seen(w).has("flour"),"chain: flour is not a cooked meal")
	expect(w.step(PUMPKIN_TIME,true),"chain: pumpkin ripens")
	must(w,A,"harvest",pumpkin,"","chain: harvest pumpkin")
	expect(held(w,"pumpkin")==1,"chain: one pumpkin")
	refuse(w,A,"cook",STOVE,"pumpkin_pie","chain: pie without an egg fails atomically")
	refuse(w,A,"queue_cook",STOVE,"pumpkin_pie","chain: queued pie without an egg fails atomically")
	# egg: feed recipe (unchanged) -> hen -> egg
	must(w,A,"cook",STOVE,"feed","chain: cook feed")
	expect(w.step(float(FEED.time)+1.0,true),"chain: feed done")
	must(w,A,"claim_cook",STOVE,"","chain: claim feed")
	expect(held(w,"feed")==int(FEED.yield) and held(w,"wheat")==1,"chain: feed +4 from 1 wheat")
	must(w,A,"feed",HEN,"","chain: feed the hen")
	expect(w.step(61.0,true),"chain: hen lays")
	must(w,A,"egg",HEN,"","chain: collect egg")
	expect(held(w,"egg")==1,"chain: one egg")
	var before:=inv(w)
	cooked0=int(w.state.players[A].get("cooked",0))
	var t0:=float(w.state.time)
	must(w,A,"cook",STOVE,"pumpkin_pie","chain: bake pumpkin pie")
	expect(diff(before,inv(w))=={"pumpkin":-1,"flour":-1,"egg":-1},"chain: pie takes exactly pumpkin/flour/egg one each: "+str(diff(before,inv(w))))
	var job=dev(w,STOVE).get("job",{})
	expect(job is Dictionary and job.get("kind")=="pumpkin_pie" and int(job.get("yield",0))==PIE_YIELD and close(float(job.get("ready",0)),t0+PIE_TIME),"chain: stove job snapshots yield 4 and 120 s: "+str(job))
	expect(w.step(PIE_TIME-1.0,true),"chain: 119 s of baking")
	refuse(w,A,"claim_cook",STOVE,"","chain: pie not ready at 119 s")
	expect(w.step(2.0,true),"chain: pie done")
	must(w,A,"claim_cook",STOVE,"","chain: claim pies")
	expect(held(w,"pumpkin_pie")==PIE_YIELD,"chain: four pumpkin pies")
	expect(int(w.state.players[A].get("cooked",0))==cooked0+1 and meals_seen(w).get("pumpkin_pie")==true,"chain: pie counts as a cooked meal in the collection")
	var c0:=coins(w)
	must(w,A,"sell",STALL,"pumpkin_pie","chain: sell pies")
	expect(coins(w)==c0+PIE_YIELD*PIE_PRICE and held(w,"pumpkin_pie")==0,"chain: four pies sell for 4 x 80")
	# FIXTURE: one more ingredient set to cover the queue_cook snapshot.
	stock(w,A,{"pumpkin":1,"flour":1,"egg":1})
	must(w,A,"queue_cook",STOVE,"pumpkin_pie","queue pie: enqueue at the stove")
	var cooking=dev(w,STOVE).get("cooking",{})
	var active=cooking.get("active",{}) if cooking is Dictionary else {}
	expect(active is Dictionary and active.get("kind")=="pumpkin_pie" and int(active.get("yield",0))==PIE_YIELD and ints(active.get("ingredients",{}))==PIE_COST and close(float(active.get("duration",0)),PIE_TIME),"queue pie: record snapshots pumpkin/flour/egg, yield 4, 120 s: "+str(active))
	expect(held(w,"pumpkin")==0 and held(w,"flour")==0 and held(w,"egg")==0,"queue pie: ingredients charged once")
	expect(w.step(PIE_TIME+1.0,true),"queue pie: done")
	must(w,A,"claim_cook",STOVE,"","queue pie: claim")
	expect(held(w,"pumpkin_pie")==PIE_YIELD,"queue pie: four pies")

func test_tea_pudding() -> void:
	var w=from_template()
	stock(w,A,{"tea_leaf":1,"milk":1,"egg":0})
	refuse(w,A,"queue_cook",STOVE,"tea_pudding","pudding: missing egg fails atomically")
	stock(w,A,{"tea_leaf":1,"milk":1,"egg":1})
	must(w,A,"queue_cook",STOVE,"tea_pudding","pudding: queue at the stove")
	expect(held(w,"tea_leaf")==0 and held(w,"milk")==0 and held(w,"egg")==0,"pudding: charges tea, milk and egg once")
	expect(w.step(119.0,true),"pudding: advance 119 seconds")
	refuse(w,A,"claim_cook",STOVE,"","pudding: cannot claim early")
	expect(w.step(1.0,true),"pudding: advance to 120 seconds")
	must(w,A,"claim_cook",STOVE,"","pudding: claim")
	expect(held(w,"tea_pudding")==3,"pudding: produces three servings")
	expect(meals_seen(w).has("tea_pudding"),"pudding: records the meal in the collection")
	refuse(w,A,"claim_cook",STOVE,"","pudding: cannot claim twice")
	var box:=World.SHIPPING.cell_for(w.state)
	pose(w,A,Vector2(box)+Vector2(0.5,1.5))
	var before:=coins(w)
	refuse(w,A,"ship",box,JSON.stringify([[["tea_pudding",1]],59]),"pudding: rejects stale shipping total")
	must(w,A,"ship",box,JSON.stringify([[["tea_pudding",1]],60]),"pudding: ship one portion")
	expect(coins(w)==before+60 and held(w,"tea_pudding")==2,"pudding: shipping pays 60 per portion")
	pose(w,A,Vector2(STALL)+Vector2(0.5,1.5))
	must(w,A,"sell",STALL,"tea_pudding","pudding: sell remaining portions")
	expect(coins(w)==before+180 and held(w,"tea_pudding")==0,"pudding: stall matches shipping price")

func test_star_rice_ball() -> void:
	var w=from_template()
	var shore:=World.SEAWEED_CELL
	expect(World.land(shore) and not World.land(shore+Vector2i.DOWN),"seaweed is on the true coastline")
	pose(w,A,Vector2(shore)+Vector2(0.5,0.5))
	must(w,A,"axe",shore,"","seaweed: collect from the coast")
	expect(held(w,"seaweed")==1,"seaweed: one frond")
	refuse(w,A,"axe",shore,"","seaweed: cannot collect again before regrowth")
	expect(w.step(60.0,true),"seaweed: advance to regrowth")
	must(w,A,"axe",shore,"","seaweed: collect after regrowth")
	expect(held(w,"seaweed")==2,"seaweed: harvest is renewable")
	stock(w,A,{"rice":2})
	pose(w,A,Vector2(STOVE)+Vector2(0.5,1.5))
	must(w,A,"queue_cook",STOVE,"star_rice_ball","rice ball: cook with gathered seaweed")
	expect(held(w,"rice")==0 and held(w,"seaweed")==1,"rice ball: uses two rice and one seaweed")
	expect(w.step(60.0,true),"rice ball: finish cooking")
	must(w,A,"claim_cook",STOVE,"","rice ball: claim")
	expect(held(w,"star_rice_ball")==3 and meals_seen(w).has("star_rice_ball"),"rice ball: three portions and collection entry")
	refuse(w,A,"eat_rice_ball",Vector2i.ZERO,"","rice ball: no consumption outside a mine")
	var player:Dictionary=w.state.players[A]
	player.region="mine_1" # FIXTURE: exercise food with low energy without mining.
	player.mine_energy=73
	must(w,A,"eat_rice_ball",Vector2i.ZERO,"","rice ball: restore mine energy")
	expect(int(w.state.players[A].mine_energy)==93 and held(w,"star_rice_ball")==2,"rice ball: restore 20 and consume one")
	must(w,A,"eat_rice_ball",Vector2i.ZERO,"","rice ball: restore only available capacity")
	expect(int(w.state.players[A].mine_energy)==100 and held(w,"star_rice_ball")==1,"rice ball: cap energy at 100")
	refuse(w,A,"eat_rice_ball",Vector2i.ZERO,"","rice ball: full energy keeps inventory")

func test_strawberry_toast_gift() -> void:
	var w=from_template()
	stock(w,A,{"bread":1,"strawberry_jam":0})
	refuse(w,A,"queue_cook",STOVE,"strawberry_toast","toast: missing jam rejects without spending bread")
	stock(w,A,{"bread":1,"strawberry_jam":1})
	must(w,A,"queue_cook",STOVE,"strawberry_toast","toast: queue recipe")
	expect(held(w,"bread")==0 and held(w,"strawberry_jam")==0,"toast: ingredient debit")
	expect(w.step(20.0,true),"toast: finish cooking")
	must(w,A,"claim_cook",STOVE,"","toast: claim from the stove")
	expect(held(w,"strawberry_toast")==2 and meals_seen(w).has("strawberry_toast"),"toast: two portions and the meal discovery")
	var cell:Vector2i=World.bond_place(w.state,"xiaoli")[1]
	pose(w,A,Vector2(cell)+Vector2(0.5,1.5))
	var before:=World.RESIDENT_BOND.points(w.state.players[A],"xiaoli")
	must(w,A,"resident_gift",cell,"xiaoli:strawberry_toast","toast: give one to Xiaoli")
	expect(held(w,"strawberry_toast")==1 and World.RESIDENT_BOND.points(w.state.players[A],"xiaoli")==before+3,"toast: Xiaoli's favourite bonus and one portion consumed")
	must(w,A,"resident_gift",cell,"xiaoli:strawberry_toast","toast: second gift can still be given")
	expect(held(w,"strawberry_toast")==0 and World.RESIDENT_BOND.points(w.state.players[A],"xiaoli")==before+3,"toast: no extra affinity for the second gift on the same day")

func test_handcraft_rope() -> void:
	var w=from_template()
	stock(w,A,{"fiber":4,"rope":0})
	refuse(w,A,"handcraft_rope",Vector2i.ZERO,"","rope: four fiber is insufficient")
	stock(w,A,{"fiber":5})
	must(w,A,"handcraft_rope",Vector2i.ZERO,"","rope: handcraft away from a bench")
	expect(held(w,"rope")==1 and held(w,"fiber")==0,"rope: exactly five fiber for one rope")
	refuse(w,A,"handcraft_rope",Vector2i.ZERO,"","rope: no second craft after using all fiber")
	stock(w,A,{"fiber":5,"rope":1000000000})
	refuse(w,A,"handcraft_rope",Vector2i.ZERO,"","rope: output cap leaves fiber intact")

func test_jam_pot() -> void:
	var w=from_template()
	var site:=Vector2i(41,36)
	pose(w,A,stand_near(w,site))
	stock(w,A,{"stone":8,"copper_joint":1,"strawberry":2,"sugar":1})
	must(w,A,"build",site,"jam_pot","jam pot: build after picnic")
	expect(held(w,"stone")==0 and held(w,"copper_joint")==0 and w.blocked(site),"jam pot: cost and collision")
	refuse(w,A,"queue_processing",site,"strawberry_jam","jam pot: two berries are insufficient")
	stock(w,A,{"strawberry":3})
	must(w,A,"queue_processing",site,"strawberry_jam","jam pot: queue with three berries and one sugar")
	expect(held(w,"strawberry")==0 and held(w,"sugar")==0,"jam pot: exact recipe debit")
	refuse(w,A,"remove",site,"","jam pot: cannot dismantle a working station")
	expect(w.step(179.0,true),"jam pot: advance to one second before completion")
	refuse(w,A,"claim_processing",site,"","jam pot: cannot collect before 180 seconds")
	expect(w.step(1.0,true),"jam pot: finish")
	must(w,A,"claim_processing",site,"","jam pot: collect the batch")
	expect(held(w,"strawberry_jam")==2 and meals_seen(w).has("strawberry_jam"),"jam pot: two jars and the meal discovery")
	refuse(w,A,"claim_processing",site,"","jam pot: cannot collect twice")

func test_mill_queue() -> void:
	var w=from_template()
	var m:=mill_cell
	# FIXTURE: verify the mill's corn recipe before exercising the flour queue.
	stock(w,A,{"sweet_corn":1,"fiber":1})
	refuse(w,A,"queue_processing",m,"feed","mill feed: missing fiber fails atomically")
	stock(w,A,{"sweet_corn":1,"fiber":2})
	var feed_before:=held(w,"feed")
	must(w,A,"queue_processing",m,"feed","mill feed: enqueue corn and fiber")
	expect(held(w,"sweet_corn")==0 and held(w,"fiber")==0,"mill feed: charges one corn and two fiber")
	expect(w.step(59.0,true),"mill feed: advance 59 seconds")
	refuse(w,A,"claim_processing",m,"","mill feed: not ready at 59 seconds")
	expect(w.step(1.0,true),"mill feed: advance to 60 seconds")
	must(w,A,"claim_processing",m,"","mill feed: claim")
	expect(held(w,"feed")==feed_before+4,"mill feed: yields four portions")
	refuse(w,A,"claim_processing",m,"","mill feed: cannot claim twice")
	# FIXTURE: wheat for both players.
	stock(w,A,{"wheat":40})
	stock(w,B,{"wheat":10})
	for bad in ["plank","charcoal","pumpkin_pie","bread","soup","wheat",""]:
		refuse(w,A,"queue_processing",m,bad,"mill queue: recipe '%s' refused on the mill"%bad)
	refuse(w,B,"queue_processing",m,"flour","mill queue: non-owner cannot enqueue")
	stock(w,A,{"wheat":1}) # FIXTURE: one wheat short
	refuse(w,A,"queue_processing",m,"flour","mill queue: missing wheat fails atomically")
	stock(w,A,{"wheat":40})
	var ids:=queue_ids(w,m,"flour",10,"mill queue: enqueue")
	expect(held(w,"wheat")==20,"mill queue: each job charged exactly 2 wheat")
	var c:=q(w,m)
	var records:Array=[]
	if c.get("active") is Dictionary and not (c.active as Dictionary).is_empty():records.append(c.active)
	if c.get("waiting") is Array:records.append_array(c.waiting)
	var snap_ok:=records.size()==10
	for e in records:
		if e.get("owner")!=A or e.get("kind")!="flour" or ints(e.get("ingredients",{}))!=FLOUR_COST or int(e.get("yield",0))!=FLOUR_YIELD or not close(float(e.get("duration",0)),FLOUR_TIME):snap_ok=false
	expect(snap_ok,"mill queue: every record snapshots owner, wheat 2, yield 1, 60 s")
	expect(active_id(c)==(ids[0] if ids.size()>0 else "x") and ids_of(c.get("waiting",[]))==ids.slice(1),"mill queue: FIFO active + nine waiting")
	expect(not dev(w,m).has("job") and dev(w,m).get("auto_enabled")==false and int(dev(w,m).get("input_wheat",-1))==0,"mill queue: no job, auto off, buffer untouched")
	refuse(w,A,"queue_processing",m,"flour","mill queue: eleventh job refused (capacity 10)")
	if ids.size()!=10:return
	refuse(w,B,"cancel_processing_job",m,ids[3],"mill queue: non-owner cannot cancel by id")
	refuse(w,B,"cancel_processing",m,"","mill queue: non-owner cannot cancel active")
	refuse(w,B,"toggle_auto_processing",m,"","mill queue: non-owner cannot toggle")
	refuse(w,A,"toggle_auto_processing",m,"","mill queue: toggle blocked while queue busy")
	refuse(w,A,"move_object",m,World.key(m+Vector2i(0,1)),"mill queue: busy mill cannot move")
	refuse(w,A,"remove",m,"","mill queue: busy mill cannot be removed")
	# FIXTURE: historical record (stored ingredients differ from today's recipe).
	for entry in q(w,m).get("waiting",[]):
		if entry is Dictionary and entry.get("id")==ids[9]:entry["ingredients"]={"wheat":3}
	var w0:=held(w,"wheat")
	must(w,A,"cancel_processing_job",m,ids[9],"mill queue: cancel historical waiting job")
	expect(held(w,"wheat")==w0+3,"mill queue: refund is the stored snapshot (3 wheat)")
	w0=held(w,"wheat")
	must(w,A,"cancel_processing_job",m,ids[5],"mill queue: cancel waiting job")
	expect(held(w,"wheat")==w0+2 and held(w,"flour")==0,"mill queue: exact 2 wheat refund, no flour")
	expect(all_ids(q(w,m))==[ids[0],ids[1],ids[2],ids[3],ids[4],ids[6],ids[7],ids[8]],"mill queue: only cancelled jobs removed, order kept")
	refuse(w,A,"cancel_processing_job",m,ids[5],"mill queue: no double refund")
	refuse(w,A,"cancel_processing_job",m,"0".repeat(32),"mill queue: unknown id")
	w0=held(w,"wheat")
	must(w,A,"cancel_processing",m,"","mill queue: cancel the active job")
	expect(held(w,"wheat")==w0+2 and active_id(q(w,m))==ids[1],"mill queue: active refunded, next promoted")
	expect(w.step(FLOUR_TIME-1.0,true),"mill queue: 59 s")
	expect(ready_n(q(w,m))==0,"mill queue: nothing ready before 60 s")
	expect(w.step(1.5,true),"mill queue: first job completes")
	expect(ids_of(q(w,m).get("ready",[]))==[ids[1]],"mill queue: exactly the promoted job ready")
	expect(buffer_empty(dev(w,m)) and not dev(w,m).has("job"),"mill queue: completion never fills the automatic output buffer")
	refuse(w,A,"cancel_processing_job",m,ids[1],"mill queue: ready job never cancellable")
	refuse(w,B,"claim_processing",m,"","mill queue: non-owner cannot claim")
	w0=held(w,"wheat")
	for id in [ids[2],ids[3],ids[4],ids[6],ids[7],ids[8]]:must(w,A,"cancel_processing_job",m,id,"mill queue: cancel "+id.left(6))
	expect(held(w,"wheat")==w0+12,"mill queue: six remaining jobs refunded exactly")
	expect(held(w,"wheat")==40-2*1+1,"mill queue: wheat ledger = start - one milled job + historical bonus")
	var cooked0:=int(w.state.players[A].get("cooked",0))
	must(w,A,"claim_processing",m,"","mill queue: claim flour")
	expect(held(w,"flour")==1 and int(w.state.players[A].get("cooked",0))==cooked0 and not meals_seen(w).has("flour"),"mill queue: flour +1, never a meal")
	refuse(w,A,"claim_processing",m,"","mill queue: nothing left to claim")
	var dest:=m+Vector2i(0,1)
	must(w,A,"move_object",m,World.key(dest),"mill queue: idle mill moves")
	expect(dev(w,dest).get("type")=="mill" and dev(w,m).is_empty(),"mill queue: mill relocated")
	var kits:=held(w,"mill_kit")
	must(w,A,"remove",dest,"","mill queue: idle mill removed")
	expect(dev(w,dest).is_empty() and held(w,"mill_kit")==kits+1,"mill queue: removal refunds one mill_kit")

func test_legacy_sawmill_unchanged() -> void:
	var w=from_template()
	# FIXTURE: sawmill kit materials and wheat.
	stock(w,A,{"wood":100,"stone":20,"wheat":10})
	var o:=find_area(w,Vector2i(1,1),"legacy sawmill")
	if o.x<0:return
	must(w,A,"craft",bench_cell,"sawmill_kit","sawmill: craft kit")
	must(w,A,"build",o,"sawmill","sawmill: build")
	var s:=dev(w,o)
	expect(s.get("type")=="sawmill" and int(s.get("input_wood",-1))==0 and not s.has("input_wheat"),"sawmill: legacy input_wood shape, no mill buffer")
	refuse(w,A,"queue_processing",o,"flour","sawmill: flour refused on a sawmill")
	stock(w,A,{"wood":0}) # FIXTURE: wheat only
	refuse(w,A,"feed_processing",o,"","sawmill: feeding wheat into a sawmill refused")
	stock(w,A,{"wood":8})
	must(w,A,"feed_processing",o,"","sawmill: wood feed still works")
	expect(int(dev(w,o).get("input_wood",0))==4 and held(w,"wheat")==10,"sawmill: 4 wood buffered, wheat untouched")
	must(w,A,"queue_processing",o,"plank","sawmill: plank queue still works")

func test_mill_material_box() -> void:
	var w=from_template()
	var m:=mill_cell
	var pc:=m+Vector2i(1,0)
	var sc:=m+Vector2i(0,1)
	stock(w,A,{"wood":200}) # FIXTURE: chest wood
	must(w,A,"build",pc,"private_chest","box: A's private chest beside the mill")
	must(w,A,"build",sc,"chest","box: shared chest beside the mill")
	stock(w,B,{"wheat":4}) # FIXTURE
	refuse(w,B,"prepare_material_box",m,World.key(sc),"box: visitor cannot source A's owner-only mill")
	stock(w,A,{"wheat":2}) # FIXTURE
	must(w,A,"deposit",pc,"wheat","box: deposit 1 wheat")
	var prep:=must(w,A,"prepare_material_box",m,World.key(pc),"box: prepare private chest at the mill")
	var box:=str(prep.get("source_id",""))
	expect(hex32(box),"box: chest id issued")
	var sq:=quote(w,"queue_processing",m,"flour",pc,box)
	expect(ints(sq.plan.get("from_backpack",{}))=={"wheat":1} and ints(sq.plan.get("from_chest",{}))=={"wheat":1},"box: quoted split 1 backpack + 1 chest: "+str(sq.plan))
	refuse(w,B,"queue_processing",m,sq.extra,"box: visitor sourced enqueue refused")
	var r:=must(w,A,"queue_processing",m,sq.extra,"box: sourced flour enqueue")
	expect(r.get("source_cell")==World.key(pc) and ints(r.get("from_chest",{}))=={"wheat":1},"box: server confirms box and split")
	expect(held(w,"wheat")==0 and int(dev(w,pc).get("items",{}).get("wheat",0))==0,"box: backpack and chest each debited one wheat")
	var c:=q(w,m)
	expect(all_ids(c).size()==1 and ints(c.get("active",{}).get("ingredients",{}))==FLOUR_COST,"box: one job snapshotting wheat 2")
	must(w,A,"cancel_processing",m,"","box: cancel sourced job")
	expect(held(w,"wheat")==2 and int(dev(w,pc).get("items",{}).get("wheat",0))==0,"box: exact 2 wheat refund to the backpack")
	stock(w,A,{"wheat":1}) # FIXTURE
	must(w,A,"deposit",pc,"wheat","box: deposit the only wheat")
	var short:=Sources.encode("flour",World.key(pc),box,"0".repeat(16))
	refuse(w,A,"queue_processing",m,short,"box: 1 chest wheat cannot cover 2 (atomic)")

func test_mill_buffers_and_auto() -> void:
	var w=from_template()
	var m:=mill_cell
	stock(w,A,{"wheat":0,"wood":20}) # FIXTURE: wood only
	refuse(w,A,"feed_processing",m,"","auto: wood is never fed into the mill")
	expect(int(dev(w,m).get("input_wheat",-1))==0 and int(dev(w,m).get("input_wood",0))==0,"auto: no buffer after refusal")
	stock(w,A,{"wheat":10}) # FIXTURE
	must(w,A,"feed_processing",m,"","auto: feed wheat")
	var d:=10-held(w,"wheat")
	expect(d>0 and int(dev(w,m).get("input_wheat",-1))==d and held(w,"wood")==20,"auto: input_wheat holds exactly the wheat taken (%d), wood untouched"%d)
	must(w,A,"unload_processing_input",m,"","auto: unload buffered wheat")
	expect(held(w,"wheat")==10 and int(dev(w,m).get("input_wheat",-1))==0 and held(w,"wood")==20,"auto: unload returns wheat, never wood")
	must(w,A,"feed_processing",m,"","auto: feed again")
	var d2:=10-held(w,"wheat")
	for action in ["feed_processing","unload_processing_input","collect_processing_output","toggle_auto_processing"]:
		refuse(w,B,action,m,"","auto: visitor %s refused"%action)
	var ids:=queue_ids(w,m,"flour",1,"auto: manual job while wheat is buffered")
	expect(int(dev(w,m).get("input_wheat",-1))==d2 and held(w,"wheat")==10-d2-2,"auto: manual queue charges the backpack, buffer untouched")
	refuse(w,A,"toggle_auto_processing",m,"","auto: toggle blocked by active job")
	expect(w.step(FLOUR_TIME+1.0,true),"auto: manual job completes")
	expect(ready_n(q(w,m))==1 and int(dev(w,m).get("input_wheat",-1))==d2 and not dev(w,m).has("job"),"auto: manual queue never consumes the buffer")
	refuse(w,A,"toggle_auto_processing",m,"","auto: toggle blocked by unclaimed flour")
	must(w,A,"claim_processing",m,"","auto: claim manual flour")
	must(w,A,"toggle_auto_processing",m,"","auto: enable automatic milling on an empty queue")
	var md:=dev(w,m)
	expect(md.get("auto_enabled")==true and empty_queue(md) and int(md.get("input_wheat",-1))==d2,"auto: auto on, queue gone, buffer preserved")
	refuse(w,A,"queue_processing",m,"flour","auto: auto mode rejects manual queue")
	refuse(w,A,"start_processing",m,"flour","auto: auto mode rejects start_processing")
	var batches:=floori(d2/2.0)
	var saw_auto:=false
	var job_ok:=true
	for i in ceili(batches*(FLOUR_TIME+4.0)/2.0)+10:
		w.step(2.0,true)
		var job=dev(w,m).get("job",{})
		if job is Dictionary and job.get("auto",false):
			saw_auto=true
			if job.get("kind")!="flour" or ints(job.get("ingredients",{}))!=FLOUR_COST:job_ok=false
	md=dev(w,m)
	expect(saw_auto and job_ok,"auto: automatic flour jobs consume wheat 2")
	expect(batches>0 and int(md.get("items",{}).get("flour",0))==batches and int(md.get("input_wheat",-1))==d2-2*batches,"auto: %d buffered wheat -> %d flour in the output buffer"%[d2,batches])
	expect(held(w,"flour")==1,"auto: automatic output never enters the backpack by itself")
	refuse(w,A,"claim_processing",m,"","auto: automatic output is not a manual claim")
	var f0:=held(w,"flour")
	must(w,A,"collect_processing_output",m,"","auto: collect flour buffer")
	expect(held(w,"flour")==f0+batches and buffer_empty(dev(w,m)),"auto: collected flour, buffer empty")
	must(w,A,"toggle_auto_processing",m,"","auto: disable")
	must(w,A,"queue_processing",m,"flour","auto: manual queue allowed again when idle and off")
	expect(ids.size()==1,"auto: fixture ids")

func test_mill_conveyor_chain() -> void:
	var w=from_template()
	var o:=find_area(w,Vector2i(5,1),"conveyor chain")
	if o.x<0:return
	# FIXTURE: chest wood, conveyor kits, wheat.
	stock(w,A,{"wood":100,"conveyor_kit":2,"wheat":8})
	var src:=o
	var in_belt:=o+Vector2i(1,0)
	var m:=o+Vector2i(2,0)
	var out_belt:=o+Vector2i(3,0)
	var dst:=o+Vector2i(4,0)
	must(w,A,"build",src,"private_chest","chain: source chest")
	must(w,A,"build",in_belt,"conveyor","chain: wheat belt")
	craft_and_build_mill(w,m,"chain")
	must(w,A,"build",out_belt,"conveyor","chain: flour belt")
	must(w,A,"build",dst,"private_chest","chain: output chest")
	refuse(w,A,"configure_conveyor",in_belt,"filter:soup","chain: unknown/meal filter refused")
	refuse(w,A,"configure_conveyor",in_belt,"filter:","chain: empty filter refused")
	for spec in [[in_belt,"dir:1"],[in_belt,"filter:wheat"],[out_belt,"dir:1"],[out_belt,"filter:flour"]]:
		must(w,A,"configure_conveyor",spec[0],spec[1],"chain: configure "+str(spec[1]))
	expect(dev(w,in_belt).get("filter")=="wheat" and dev(w,out_belt).get("filter")=="flour","chain: belts filter wheat and flour")
	must(w,A,"toggle_conveyor",in_belt,"","chain: enable wheat belt")
	must(w,A,"toggle_conveyor",out_belt,"","chain: enable flour belt")
	for i in 8:must(w,A,"deposit",src,"wheat","chain: deposit wheat %d"%i)
	must(w,A,"toggle_auto_processing",m,"","chain: enable automatic mill")
	var flour0:=held(w,"flour")
	var saw_auto:=false
	var t0:=float(w.state.time)
	for i in 220:
		expect(w.step(2.0,true),"chain: tick %d"%i)
		var job=dev(w,m).get("job",{})
		if job is Dictionary and job.get("auto",false):saw_auto=true
	print("FIXTURE %s: conveyor chain advanced %.1fs of world time in 220 World.step frames"%[LABEL,float(w.state.time)-t0])
	var md:=dev(w,m)
	expect(saw_auto,"chain: belt-fed automatic flour job ran")
	expect(int(dev(w,dst).get("items",{}).get("flour",0))==4,"chain: 8 wheat -> 4 flour delivered to the output chest: "+str(dev(w,dst).get("items")))
	expect(int(dev(w,src).get("items",{}).get("wheat",0))==0 and int(md.get("input_wheat",-1))==0 and buffer_empty(md) and not md.has("job"),"chain: source, buffer and output drained")
	expect((dev(w,in_belt).get("items",{}) as Dictionary).is_empty() and (dev(w,out_belt).get("items",{}) as Dictionary).is_empty(),"chain: belts empty")
	expect(empty_queue(md) and held(w,"flour")==flour0,"chain: automation creates no manual records and never fills the backpack")

func test_mill_rejects_wood_then_buffers_wheat() -> void:
	var w=from_template()
	var o:=find_area(w,Vector2i(3,1),"wood belt")
	if o.x<0:return
	stock(w,A,{"wood":100,"conveyor_kit":1}) # FIXTURE
	var chest:=o
	var belt:=o+Vector2i(1,0)
	var m:=o+Vector2i(2,0)
	must(w,A,"build",chest,"private_chest","wood belt: chest")
	must(w,A,"build",belt,"conveyor","wood belt: belt")
	craft_and_build_mill(w,m,"wood belt")
	must(w,A,"configure_conveyor",belt,"dir:1","wood belt: point at the mill")
	must(w,A,"configure_conveyor",belt,"filter:wood","wood belt: wood filter")
	must(w,A,"toggle_conveyor",belt,"","wood belt: enable")
	for i in 4:must(w,A,"deposit",chest,"wood","wood belt: deposit wood %d"%i)
	must(w,A,"toggle_auto_processing",m,"","wood belt: automatic mill on")
	for i in 20:expect(w.step(2.0,true),"wood belt: tick %d"%i)
	var md:=dev(w,m)
	var on_belt:=int(dev(w,belt).get("items",{}).get("wood",0))
	expect(int(md.get("input_wheat",-1))==0 and int(md.get("input_wood",0))==0 and not md.has("job") and buffer_empty(md),"wood belt: mill accepts no wood")
	expect(on_belt==1 and int(dev(w,chest).get("items",{}).get("wood",0))==3,"wood belt: wood waits on the belt, nothing lost")
	# Same site: manual-queue mill fed by a wheat belt (buffer/queue coexistence).
	must(w,A,"toggle_auto_processing",m,"","coexist: automatic mill off")
	must(w,A,"toggle_conveyor",belt,"","coexist: belt off")
	must(w,A,"unload_conveyor",belt,"","coexist: unload stuck wood")
	must(w,A,"configure_conveyor",belt,"filter:wheat","coexist: wheat filter")
	must(w,A,"toggle_conveyor",belt,"","coexist: belt on")
	stock(w,A,{"wheat":6}) # FIXTURE
	for i in 4:must(w,A,"deposit",chest,"wheat","coexist: deposit wheat %d"%i)
	var ids:=queue_ids(w,m,"flour",1,"coexist: manual job from the backpack")
	expect(held(w,"wheat")==0,"coexist: manual job charged 2 backpack wheat")
	for i in 35:expect(w.step(2.0,true),"coexist: tick %d"%i)
	md=dev(w,m)
	expect(int(md.get("input_wheat",-1))==4,"coexist: belt wheat buffered on the manual mill, never consumed: "+str(md.get("input_wheat")))
	expect(ids_of(q(w,m).get("ready",[]))==ids and not md.has("job") and buffer_empty(md) and md.get("auto_enabled")==false,"coexist: exactly the manual job ready, no automatic job/output")
	var f0:=held(w,"flour")
	must(w,A,"claim_processing",m,"","coexist: claim manual flour")
	expect(held(w,"flour")==f0+1,"coexist: one flour")
	must(w,A,"unload_processing_input",m,"","coexist: unload buffered wheat")
	expect(held(w,"wheat")==4 and int(dev(w,m).get("input_wheat",-1))==0,"coexist: buffered wheat returned")

func test_save_reload_and_schema() -> void:
	var w=from_template()
	w.state.time = 2 * World.WEATHER.DAYS_PER_SEASON * World.WEATHER.DAY_SECONDS
	var m:=mill_cell
	stock(w,A,{"wheat":12,"conveyor_kit":1}) # FIXTURE
	set_coins(w,A,PUMPKIN_SEED_PRICE) # FIXTURE
	var o:=find_area(w,Vector2i(2,1),"save plot")
	if o.x<0:return
	var plot:=o
	var belt:=o+Vector2i(1,0)
	must(w,A,"buy",STALL,"pumpkin","save: buy pumpkin seed")
	must(w,A,"hoe",plot,"","save: hoe")
	must(w,A,"seed",plot,"pumpkin","save: sow pumpkin")
	must(w,A,"water",plot,"","save: water")
	must(w,A,"build",belt,"conveyor","save: belt")
	must(w,A,"configure_conveyor",belt,"filter:flour","save: flour filter")
	must(w,A,"feed_processing",m,"","save: buffer wheat")
	var buffered:=int(dev(w,m).get("input_wheat",-1))
	var ids:=queue_ids(w,m,"flour",2,"save: enqueue")
	expect(w.step(30.0,true),"save: 30 s of growth and milling")
	expect(w.save(),"save: explicit save after the step")
	var text:=FileAccess.get_file_as_string(w.save_path)
	var parser:=JSON.new()
	var ok:=parser.parse(text)==OK and parser.data is Dictionary
	var doc:Dictionary=parser.data if ok else {}
	expect(int(doc.get("version",0))==SAVE_VERSION and int(doc.get("version",0))==int(Schema.VERSION),"save: written at version 26")
	var mk:=World.key(m)
	var ck:=World.key(plot)
	var bk:=World.key(belt)
	var sm=doc.get("objects",{}).get(mk,{})
	expect(sm is Dictionary and sm.get("type")=="mill" and int(sm.get("input_wheat",-1))==buffered and sm.get("processing") is Dictionary,"save: mill, input_wheat and queue persisted")
	expect(doc.get("crops",{}).get(ck,{}).get("kind")=="pumpkin","save: pumpkin plot persisted")
	expect(doc.get("objects",{}).get(bk,{}).get("filter")=="flour","save: flour belt filter persisted")
	var copy:=dir.path_join("reload-%d.json"%serial)
	write_text(copy,text)
	var loaded=World.new()
	expect(loaded.load_world(copy),"save: reload passes real SaveSchema validation")
	attach(loaded)
	expect(all_ids(q(loaded,m))==ids and int(dev(loaded,m).get("input_wheat",-1))==buffered,"save: queue order and buffer survive reload")
	expect(close(float(crop(loaded,plot).get("growth",-1)),30.0) and crop(loaded,plot).get("wet")==true,"save: pumpkin growth survives reload")
	expect(loaded.step(31.0,true),"save: reloaded world continues")
	must(loaded,A,"claim_processing",m,"","save: claim flour after reload")
	expect(held(loaded,"flour")==1,"save: flour claimed after reload")
	expect(sm is Dictionary and doc.get("crops",{}).has(ck) and doc.get("objects",{}).has(bk),"schema: mutation fixtures present in the real save")
	if not (sm is Dictionary and doc.get("crops",{}).has(ck) and doc.get("objects",{}).has(bk)):return
	for case_id in ["unmodified","wheat_four","flour_buffer","ripe_exact","wheat_belt"]:
		expect(schema_case(text,case_id,mk,ck,bk),"schema: accepts "+case_id)
	for case_id in ["wheat_negative","wheat_fraction","wheat_text","wheat_huge","flour_on_sawmill","plank_on_mill","plank_buffer","plank_auto_job","job_id","crop_case","crop_seed","crop_overgrown","belt_filter"]:
		expect(not schema_case(text,case_id,mk,ck,bk),"schema: rejects "+case_id)

func schema_case(text:String,case_id:String,mk:String,ck:String,bk:String) -> bool:
	var parser:=JSON.new()
	if parser.parse(text)!=OK or not parser.data is Dictionary:return false
	var doc:Dictionary=parser.data
	var objects:Dictionary=doc.get("objects",{})
	var mill:Dictionary=objects.get(mk,{})
	var plot:Dictionary=doc.get("crops",{}).get(ck,{})
	var belt:Dictionary=objects.get(bk,{})
	var proc=mill.get("processing",{})
	var active=proc.get("active",{}) if proc is Dictionary else {}
	if not active is Dictionary:active={}
	match case_id:
		"unmodified":pass
		"wheat_four":mill["input_wheat"]=4
		"flour_buffer":
			mill.erase("processing")
			mill["items"]={"flour":2}
		"ripe_exact":plot["growth"]=PUMPKIN_TIME
		"wheat_belt":belt["filter"]="wheat"
		"wheat_negative":mill["input_wheat"]=-1
		"wheat_fraction":mill["input_wheat"]=2.5
		"wheat_text":mill["input_wheat"]="4"
		"wheat_huge":mill["input_wheat"]=1000000
		"flour_on_sawmill":mill["type"]="sawmill"
		"plank_on_mill":active["kind"]="plank"
		"plank_buffer":
			mill.erase("processing")
			mill["items"]={"plank":2}
		"plank_auto_job":
			mill.erase("processing")
			mill["job"]={"kind":"plank","owner":A,"ready":float(doc.get("time",0))+5.0,"ingredients":{"wood":4},"yield":2,"auto":true}
		"job_id":active["id"]="NOT-A-HEX-ID"
		"crop_case":plot["kind"]="Pumpkin"
		"crop_seed":plot["kind"]="pumpkin_seed"
		"crop_overgrown":plot["growth"]=PUMPKIN_TIME+0.5
		"belt_filter":belt["filter"]="flour_x"
	serial+=1
	var path:=dir.path_join("schema-%d.json"%serial)
	write_text(path,JSON.stringify(doc))
	var probe=World.new()
	return probe.load_world(path)

## Legacy: a real save without bakery content edited to version 23 / 22 loads
## (additive default migration); a version-23 document carrying a mill or a
## future version is rejected.
func test_legacy_saves() -> void:
	var w=new_world()
	stock(w,A,{"wood":100,"stone":50}) # FIXTURE
	var o:=find_area(w,Vector2i(3,1),"legacy site")
	if o.x<0:return
	must(w,A,"build",o,"bench","legacy: bench")
	must(w,A,"craft",o,"sawmill_kit","legacy: sawmill kit")
	must(w,A,"build",o+Vector2i(2,0),"sawmill","legacy: sawmill")
	var ids:=queue_ids(w,o+Vector2i(2,0),"plank",1,"legacy: plank job")
	expect(w.save(),"legacy: save")
	var parser:=JSON.new()
	var ok:=parser.parse(FileAccess.get_file_as_string(w.save_path))==OK and parser.data is Dictionary
	expect(ok,"legacy: captured save parses")
	if not ok:return
	var base:Dictionary=parser.data
	var v23:Dictionary=base.duplicate(true)
	v23.version=23
	v23.erase("flower_nursery")
	v23.regions.erase("tianwei")
	v23.erase("salt_pan")
	v23.regions.erase("beimen")
	var p23:=dir.path_join("legacy-23.json")
	write_text(p23,JSON.stringify(v23))
	var l23=World.new()
	expect(l23.load_world(p23),"legacy: version-23 save without bakery content loads")
	expect(int(l23.state.version)==int(Schema.VERSION),"legacy: v23 stamped to the current version on load")
	var saw:Dictionary=l23.state.objects.get(World.key(o+Vector2i(2,0)),{})
	expect(saw.get("type")=="sawmill" and int(saw.get("input_wood",-1))==0 and all_ids(saw.get("processing",{}) if saw.get("processing") is Dictionary else {})==ids,"legacy: sawmill input_wood and queue preserved")
	var v22:Dictionary=base.duplicate(true)
	v22.erase("public_kitchen")
	v22.version=22
	v22.erase("flower_nursery")
	v22.regions.erase("tianwei")
	v22.erase("salt_pan")
	v22.regions.erase("beimen")
	var p22:=dir.path_join("legacy-22.json")
	write_text(p22,JSON.stringify(v22))
	expect(World.new().load_world(p22),"legacy: version-22 save still loads")
	var future:Dictionary=base.duplicate(true)
	future.version=SAVE_VERSION+1
	var pf:=dir.path_join("future.json")
	write_text(pf,JSON.stringify(future))
	expect(not World.new().load_world(pf),"legacy: future version rejected")
	var tp:=JSON.new()
	if tp.parse(template_text)==OK and tp.data is Dictionary:
		var t24:Dictionary=tp.data
		var p24:=dir.path_join("template-24.json")
		write_text(p24,JSON.stringify(t24))
		expect(World.new().load_world(p24),"legacy: version-24 world with a mill accepted")
		var old:Dictionary=t24.duplicate(true)
		old.version=23
		var po:=dir.path_join("template-as-23.json")
		write_text(po,JSON.stringify(old))
		expect(not World.new().load_world(po),"legacy: version-23 document carrying a mill rejected")
	else:
		expect(false,"legacy: template save available for version checks")
