extends SceneTree
## Chapter 3 Tianwei flower nursery through the REAL World.act / World.step /
## World.save / World.load_world path (contract test_flower_world).
##
## SEEDED FIXTURE, NOT NORMAL PLAY (disclosed; each write is labelled `FIXTURE`):
##  * chapter 2 completion: tea_ceramics records are written as a finished
##    comparison (comparison_complete) instead of playing chapter 2;
##  * state.picnic=true and the players are placed at the Yingge transfer with
##    yingge/maokong already visited (chapter 1 / tea travel not replayed);
##  * players are teleported (pose) within reach before actions;
##  * some backpack stock (blue_dye, flowers, wood/stone, flour/sugar) and one
##    temporary seed removal (reserve rejection) are written directly.
## EARNED through act()/step(): letter, transit to Tianwei (route gate, arrival,
## travel_book.visited), intro starter seeds, hoe/seed/water/grow/harvest on
## nursery beds, seed saving, dyeing, sugar purchases, order shipment, shared
## garden donations, report + memento, home seed purchase and home planting.
## World time moves only through World.step(dt, true). Saves go to one fresh
## random directory under TEMP; cleanup removes only that directory.
const World=preload("res://scripts/world.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const Shipping=preload("res://scripts/shipping.gd")
const Weather=preload("res://scripts/weather.gd")
const Transit=preload("res://scripts/transit.gd")

const A:="tok-flower-alice-SECRET"
const B:="tok-flower-bob-SECRET"
const C:="tok-flower-carol-SECRET"
const REJECT:="田尾花圃只開放育苗床照顧和花圃工作台。"
const HOME_SEED:="完成田尾花圃的第三章後，小栗才會進花卉種子。"
const FOREIGN:="這是其他島民的育苗床"
const STALL:=Vector2i(43,29)
const YINGGE_TRANSFER:=Vector2i(12,25)
const NOT_SELLABLE:=["bluebell_seed","orange_blossom_seed","chime_herb_seed","blue_dye","sugar"]

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
	dir=base.path_join("flower-world-"+Crypto.new().generate_random_bytes(8).hex_encode())
	if DirAccess.dir_exists_absolute(dir):
		expect(false,"refuse to adopt an existing test directory")
		finish()
		return
	DirAccess.make_dir_recursive_absolute(dir)
	test_catalog()
	test_chapter_flow()
	test_rain()
	finish()

func finish() -> void:
	if not dir.is_empty() and DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)
	print("FLOWER_WORLD_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)

# ------------------------------------------------------------------ helpers

func act(w,token:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return w.act(token,"fw-%d"%serial,action,p,extra)

func pose(w,token:String,at:Vector2) -> void:
	w.state.players[token].x=at.x # FIXTURE teleport within the current region
	w.state.players[token].y=at.y

func near(w,token:String,cell:Vector2i) -> void:
	pose(w,token,Vector2(cell)+Vector2(0.5,1.5))

func inv(w,token:String) -> Dictionary:
	return w.state.players[token].inventory

func held(w,token:String,item:String) -> int:
	return int(inv(w,token).get(item,0))

func rec(w,token:String) -> Dictionary:
	return Flower.own_record(w.state,token)

func snap(w) -> String:
	return JSON.stringify(w.state)

func unlock(w,token:String) -> void:
	var r:Dictionary=Tea.FRESH.duplicate(true) # FIXTURE finished chapter-2 comparison
	r.intro=true;r.potter=true;r.reused=true;r.reuse_count=1
	r.trials={"jar":true,"fiber":true};r.tea_discussed=true;r.comparison_complete=true
	w.state.tea_ceramics.players[token]=r

func at_yingge(w,token:String) -> void:
	var p:Dictionary=w.state.players[token] # FIXTURE chapter-2 travel already done
	p.region="yingge"
	p.travel_book.visited.maokong=true
	p.travel_book.visited.yingge=true
	pose(w,token,Vector2(13.5,25.5))

func new_world(name:String):
	var w=World.new()
	w.save_path=dir.path_join(name+".json")
	return w

func tianwei_crops(w) -> Dictionary:
	return w.state.regions[Flower.REGION].crops

func bed(x:int,y:int) -> Vector2i:
	return Flower.NURSERY_BEDS.position+Vector2i(x,y)

## Waters every listed plot of `token` (in its current region) and steps the
## world until all are mature (re-watering after each midnight).
func grow(w,token:String,cells:Array) -> bool:
	for i in 80:
		var all_ready:=true
		for c in cells:
			var crop:Dictionary=tianwei_crops(w).get(World.key(c),{})
			if crop.get("kind","")=="":return false
			if float(crop.growth)>=float(World.CROPS[crop.kind].time):continue
			all_ready=false
			if not crop.get("wet",false):
				near(w,token,c)
				if not act(w,token,"water",c).ok:return false
		if all_ready:return true
		if not w.step(10.0,true):return false
	return false

func harvest_all(w,token:String,cells:Array) -> void:
	for c in cells:
		near(w,token,c)
		var r:=act(w,token,"harvest",c)
		expect(r.ok,"harvest own bed %s: %s"%[str(c),r.message])

func free_home_cell(w,avoid:Array) -> Vector2i:
	for y in range(36,50):
		for x in range(24,56):
			var c:=Vector2i(x,y)
			var k:=World.key(c)
			if c in avoid or not w.is_land(c) or w.water(c) or w.protected(c) or w.blocked(c) or w.resource(c)!="":continue
			if w.state.crops.has(k) or w.state.objects.has(k) or w.state.ground.has(k) or w.state.roofs.has(k) or w.state.forest.has(k):continue
			return c
	return Vector2i(-1,-1)

# ------------------------------------------------------------------ catalog

func test_catalog() -> void:
	for kind in Flower.FLOWERS:
		expect(World.CROPS.get(kind)==Flower.CROPS[kind],"World.CROPS.%s equals FlowerNursery.CROPS"%kind)
		var crop:Dictionary=World.CROPS.get(kind,{})
		expect(int(crop.get("price",0))>=int(crop.get("seed_price",1)),"%s price >= seed_price (1:1 seed saving creates no coins)"%kind)
	expect(World.RECIPES.get("garden_cookie")==Flower.COOKIE.garden_cookie,"World.RECIPES.garden_cookie equals FlowerNursery.COOKIE")
	expect(int(World.OTHER_SALES.get("garden_cookie",0))==Flower.COOKIE_PRICE,"garden_cookie sells for 36")
	for id in Flower.NAMES:
		expect(World.NAMES.get(id)==Flower.NAMES[id],"World.NAMES.%s equals FlowerNursery.NAMES"%id)
	expect(World.RECIPES.has("garden_cookie") and World.RECIPES.has("salt_grilled_fish"),"The regional recipes remain in the expanded catalog")
	var prices:Dictionary=Shipping.prices(World.CROPS,World.FISH,World.OTHER_SALES)
	for id in NOT_SELLABLE:
		expect(not prices.has(id),"shipping prices never include %s"%id)
		expect(not World.OTHER_SALES.has(id) and not World.CROPS.has(id) and not World.FISH.has(id),"%s is not in CROPS/FISH/OTHER_SALES (stall sell branch)"%id)
	for kind in Flower.FLOWERS:expect(prices.has(kind),"flower %s is shippable at its crop price"%kind)
	expect(int(prices.get("garden_cookie",0))==36,"garden_cookie shippable at 36")
	expect(Flower.REGION not in Weather.INDOOR_REGIONS,"Tianwei is an outdoor weather region")

# ------------------------------------------------------------------ chapter flow

func test_chapter_flow() -> void:
	var w=new_world("flow")
	w.add_player(A,"Alice")
	w.add_player(B,"Bob")
	w.add_player(C,"Carol")
	w.state.picnic=true # FIXTURE chapter 1 finished (transit requires the picnic)
	expect(w.state.has("flower_nursery") and w.state.flower_nursery==Flower.fresh(),"fresh world carries FlowerNursery.fresh()")
	expect(w.state.regions.has(Flower.REGION),"fresh world has the tianwei region")

	# --- locked: no chapter-2 completion
	near(w,C,STALL)
	var before:=snap(w)
	var r:=act(w,C,"flower_letter",STALL)
	expect(not r.ok and snap(w)==before,"flower_letter refused before the tea comparison, nothing changed")

	unlock(w,A)
	unlock(w,B)
	# --- route stays closed before the letter
	at_yingge(w,A)
	w.switch_region("home")
	before=snap(w)
	r=act(w,A,"transit",YINGGE_TRANSFER,Flower.REGION)
	expect(not r.ok and w.player_region(A)=="yingge" and snap(w)==before,"transit to tianwei refused before the letter")
	var opts:Array=Transit.route_options(w.state,A,"transfer")
	expect(not opts.any(func(o):return o.region==Flower.REGION),"route_options hides tianwei before the letter")

	# --- letter at home stall (A is in yingge -> wrong region first)
	r=act(w,A,"flower_letter",STALL)
	expect(not r.ok,"flower_letter outside home refused")
	w.state.players[A].region="home" # FIXTURE back at the ferry stall for the letter
	near(w,A,STALL)
	r=act(w,A,"flower_letter",STALL)
	expect(r.ok and rec(w,A).letter,"flower_letter at the home stall: "+r.message)
	r=act(w,A,"flower_letter",STALL)
	expect(not r.ok and r.message.contains("介紹信已收下"),"second flower_letter refused: "+r.message)
	near(w,B,STALL)
	expect(act(w,B,"flower_letter",STALL).ok,"B reads the letter")

	# --- transit Yingge -> Tianwei (Transit.route_options gate), arrival + visited
	at_yingge(w,A)
	opts=Transit.route_options(w.state,A,"transfer")
	expect(opts.any(func(o):return o.region==Flower.REGION),"route_options offers tianwei after the letter")
	r=act(w,A,"transit",YINGGE_TRANSFER,Flower.REGION)
	expect(r.ok and w.player_region(A)==Flower.REGION,"transit Yingge -> Tianwei: "+r.message)
	expect(w.state.players[A].travel_book.visited.get(Flower.REGION)==true,"travel_book.visited.tianwei recorded")
	var arrived:=Vector2(float(w.state.players[A].x),float(w.state.players[A].y))
	expect(arrived.distance_to(Flower.ARRIVAL)<5.0,"arrival near the Tianwei transfer, got %s"%str(arrived))
	at_yingge(w,B)
	expect(act(w,B,"transit",YINGGE_TRANSFER,Flower.REGION).ok,"B arrives in Tianwei")

	# --- forbidden actions in Tianwei, nothing changes
	var stage:=bed(2,1)
	near(w,A,stage)
	inv(w,A).wood=40;inv(w,A).stone=40 # FIXTURE build stock (must stay untouched)
	inv(w,A).charcoal=3;inv(w,A).tiller=1;inv(w,A).seeder=1;inv(w,A).harvester=1
	var forbidden:={"build":"floor","build_area":"floor|%d|%d"%[stage.x+1,stage.y],"move_object":"%d,%d"%[stage.x+1,stage.y],
		"plant_tree":"","axe":"","pick":"","till_area":"","seed_area":"bluebell","harvest_area":"","deposit":"wood","withdraw":"wood",
		"craft":"copper_joint","cook":"soup","fish_start":"","fish_catch":"","door":"","prepare_material_box":"%d,%d"%[stage.x,stage.y]}
	for action in forbidden:
		before=snap(w)
		r=act(w,A,action,stage,forbidden[action])
		expect(not r.ok and r.message==REJECT and snap(w)==before,"Tianwei rejects %s with the nursery message: %s"%[action,r.message])
	var raw:={"version":1,"name":"flower","width":1,"height":1,"pieces":[{"kind":"floor","x":0,"y":0}]}
	var quote:Dictionary=w.quote_blueprint(A,raw,stage,0)
	expect(not quote.get("ok",true) and quote.get("message","")==REJECT,"blueprint staging rejected in Tianwei: "+str(quote.get("message","")))
	inv(w,A).erase("tiller");inv(w,A).erase("seeder");inv(w,A).erase("harvester");inv(w,A).erase("charcoal")

	# --- intro required before hoeing; intro gives starter seeds once
	before=snap(w)
	r=act(w,A,"hoe",bed(0,0))
	expect(not r.ok and snap(w)==before,"hoe before intro refused")
	near(w,A,Flower.FARMER)
	r=act(w,A,"flower_intro",Flower.FARMER)
	expect(r.ok and rec(w,A).intro,"flower_intro: "+r.message)
	for seed in Flower.STARTER:expect(held(w,A,seed)==2,"starter %s +2"%seed)
	r=act(w,A,"flower_intro",Flower.FARMER)
	expect(not r.ok and held(w,A,"bluebell_seed")==2,"second intro refused, no extra seeds")
	near(w,B,Flower.FARMER)
	expect(act(w,B,"flower_intro",Flower.FARMER).ok,"B intro")

	# --- 6-plot cap, beds only, flowers only
	var mine:Array=[]
	for i in 6:mine.append(bed(i,0))
	for c in mine:
		near(w,A,c)
		r=act(w,A,"hoe",c)
		expect(r.ok,"A hoes bed %s: %s"%[str(c),r.message])
	var seventh:=bed(6,0)
	near(w,A,seventh)
	before=snap(w)
	r=act(w,A,"hoe",seventh)
	expect(not r.ok and snap(w)==before,"7th Tianwei plot refused (cap 6): "+r.message)
	var outside:=Vector2i(Flower.NURSERY_BEDS.end.x+2,Flower.NURSERY_BEDS.position.y)
	near(w,B,outside)
	before=snap(w)
	r=act(w,B,"hoe",outside)
	expect(not r.ok and snap(w)==before,"hoe outside NURSERY_BEDS refused")
	near(w,A,mine[0])
	before=snap(w)
	r=act(w,A,"seed",mine[0],"radish")
	expect(not r.ok and snap(w)==before and held(w,A,"radish_seed")==5,"non-flower seed refused in Tianwei: "+r.message)
	var kinds:=["bluebell","orange_blossom","chime_herb"]
	for i in 3:
		near(w,A,mine[i])
		r=act(w,A,"seed",mine[i],kinds[i])
		expect(r.ok,"A sows %s: %s"%[kinds[i],r.message])
	expect(rec(w,A).planted.size()==3,"planted records all three flowers")
	var theirs:=bed(0,2)
	near(w,B,theirs)
	expect(act(w,B,"hoe",theirs).ok and act(w,B,"seed",theirs,"bluebell").ok,"B sows its own bed")

	# --- grow (step only), harvest: own only
	expect(grow(w,A,mine.slice(0,3)),"A's three flowers mature through World.step")
	near(w,B,mine[0])
	before=snap(w)
	r=act(w,B,"harvest",mine[0])
	expect(not r.ok and r.message==FOREIGN and snap(w)==before,"B cannot harvest A's bed: "+r.message)
	harvest_all(w,A,mine.slice(0,3))
	expect(held(w,A,"bluebell")==2 and held(w,A,"orange_blossom")==2 and held(w,A,"chime_herb")==1,"harvest yields 2/2/1")
	expect(rec(w,A).harvested=={"bluebell":2,"orange_blossom":2,"chime_herb":1},"harvested counts recorded: "+str(rec(w,A).harvested))
	expect(w.state.players[A].collection.crops.has("bluebell"),"collection accepts flower crops")

	# --- remove: only own empty bed
	near(w,B,mine[5])
	before=snap(w)
	expect(not act(w,B,"remove",mine[5]).ok and snap(w)==before,"B cannot remove A's empty bed")
	near(w,A,mine[5])
	expect(act(w,A,"remove",mine[5]).ok and not tianwei_crops(w).has(World.key(mine[5])),"A restores its own empty bed")
	mine.remove_at(5)

	# --- a full plant harvest against one seed packet, 60 s
	near(w,A,Flower.SEED_TABLE)
	for kind in kinds:
		r=act(w,A,"flower_save",Flower.SEED_TABLE,kind)
		expect(r.ok,"flower_save %s: %s"%[kind,r.message])
		before=snap(w)
		r=act(w,A,"flower_save_take",Flower.SEED_TABLE)
		expect(not r.ok and snap(w)==before,"take before 60 s refused")
		expect(w.step(60.0,true),"step 60 s")
		var seed_before:=held(w,A,kind+"_seed")
		r=act(w,A,"flower_save_take",Flower.SEED_TABLE)
		expect(r.ok and held(w,A,kind+"_seed")==seed_before+1,"flower_save_take %s +1 seed"%kind)
	expect(rec(w,A).saved.size()==3,"all three saved")

	# --- ship: short of flowers, then a second natural batch
	near(w,A,Flower.MARKET)
	before=snap(w)
	r=act(w,A,"flower_ship",Flower.MARKET)
	expect(not r.ok and r.message.contains("成花不足") and snap(w)==before,"ship refused when short: "+r.message)
	for i in 3:
		near(w,A,mine[i])
		expect(act(w,A,"seed",mine[i],kinds[i]).ok,"second batch %s"%kinds[i])
	expect(grow(w,A,mine.slice(0,3)),"second batch matures")
	harvest_all(w,A,mine.slice(0,3))
	near(w,A,Flower.MARKET)
	var kept_seed:=held(w,A,"bluebell_seed")
	inv(w,A).bluebell_seed=0 # FIXTURE temporary removal: reserve rule
	before=snap(w)
	r=act(w,A,"flower_ship",Flower.MARKET)
	expect(not r.ok and r.message==Flower.RESERVE_MESSAGE and snap(w)==before,"ship refused without reserve seeds: "+r.message)
	inv(w,A).bluebell_seed=kept_seed # FIXTURE restore
	var coins:=int(w.state.players[A].coins)
	var bb:=held(w,A,"bluebell")
	r=act(w,A,"flower_ship",Flower.MARKET)
	expect(r.ok and int(w.state.players[A].coins)==coins+176 and held(w,A,"bluebell")==bb-2 and rec(w,A).shipped,"flower_ship pays 176 once: "+r.message)
	before=snap(w)
	expect(not act(w,A,"flower_ship",Flower.MARKET).ok and snap(w)==before,"second shipment refused")

	# --- market: sugar daily cap, receipt replay
	coins=int(w.state.players[A].coins)
	expect(act(w,A,"flower_buy",Flower.MARKET,"sugar").ok and act(w,A,"flower_buy",Flower.MARKET,"sugar").ok,"two sugar purchases")
	before=snap(w)
	r=act(w,A,"flower_buy",Flower.MARKET,"sugar")
	expect(not r.ok and snap(w)==before and held(w,A,"sugar")==2 and int(w.state.players[A].coins)==coins-80,"third sugar refused today: "+r.message)
	var fixed:="replay-buy-1"
	var first:Dictionary=w.act(A,fixed,"flower_buy",Flower.MARKET,"chime_herb_seed")
	var coins_after:=int(w.state.players[A].coins)
	var seeds_after:=held(w,A,"chime_herb_seed")
	var again:Dictionary=w.act(A,fixed,"flower_buy",Flower.MARKET,"chime_herb_seed")
	expect(first.ok and again==first and int(w.state.players[A].coins)==coins_after and held(w,A,"chime_herb_seed")==seeds_after,"replayed request_id returns the receipt without applying twice")

	# --- dye R31 3 -> 2, 30 s
	inv(w,A).bluebell=held(w,A,"bluebell")+3 # FIXTURE three extra bluebells
	near(w,A,Flower.DYE_TABLE)
	var bb_before:=held(w,A,"bluebell")
	expect(act(w,A,"flower_dye",Flower.DYE_TABLE).ok and held(w,A,"bluebell")==bb_before-3,"flower_dye takes 3 bluebells")
	expect(not act(w,A,"flower_dye_take",Flower.DYE_TABLE).ok,"dye not ready before 30 s")
	expect(w.step(30.0,true),"step 30 s")
	expect(act(w,A,"flower_dye_take",Flower.DYE_TABLE).ok and held(w,A,"blue_dye")==2,"flower_dye_take +2 blue_dye")

	# --- save failure rolls back inventory + garden + contributors + events
	near(w,A,Flower.GARDEN_CELL)
	var good_path:String=w.save_path
	w.save_path=dir.path_join("missing-dir").path_join("deeper").path_join("world.json")
	var inv_before:=JSON.stringify(inv(w,A))
	var fn_before:=JSON.stringify(w.state.flower_nursery)
	var ev_before:=JSON.stringify(w.state.events)
	var committed:=int(w.state.committed)
	r=act(w,A,"flower_give",Flower.GARDEN_CELL)
	expect(not r.ok and r.message.contains("保存失敗"),"unwritable save path fails the donation: "+r.message)
	expect(JSON.stringify(inv(w,A))==inv_before and JSON.stringify(w.state.flower_nursery)==fn_before and JSON.stringify(w.state.events)==ev_before and int(w.state.committed)==committed,"rollback restores inventory, garden, contributors and events")
	w.save_path=good_path

	# --- two players interleaved: settles once, second takes only the remainder
	var events_before:int=w.state.events.size()
	r=act(w,A,"flower_give",Flower.GARDEN_CELL)
	var g:Dictionary=w.state.flower_nursery.garden
	expect(r.ok and int(g.given.blue_dye)==2 and int(g.contributors[A])==2+int(g.given.orange_blossom)+int(g.given.chime_herb),"A donates what it holds: "+r.message)
	var a_orange:=int(g.given.orange_blossom)
	inv(w,B).blue_dye=5;inv(w,B).orange_blossom=6;inv(w,B).chime_herb=1 # FIXTURE B's donation stock
	near(w,B,Flower.GARDEN_CELL)
	r=act(w,B,"flower_give",Flower.GARDEN_CELL)
	g=w.state.flower_nursery.garden
	expect(r.ok and int(g.given.blue_dye)==4 and held(w,B,"blue_dye")==3,"B fills only the remaining dye (takes 2 of 5)")
	expect(int(g.given.orange_blossom)==4 and held(w,B,"orange_blossom")==6-(4-a_orange),"B gives only the remaining orange blossoms")
	expect(not g.complete,"garden not complete while herbs are missing")
	inv(w,A).chime_herb=held(w,A,"chime_herb")+3;inv(w,A).blue_dye=4 # FIXTURE A brings more
	var herb_needed:=2-int(g.given.chime_herb)
	var a_herb:=held(w,A,"chime_herb")
	near(w,A,Flower.GARDEN_CELL)
	r=act(w,A,"flower_give",Flower.GARDEN_CELL)
	g=w.state.flower_nursery.garden
	expect(r.ok and g.complete and float(g.completed_at)==float(w.state.time),"A completes the garden: "+r.message)
	expect(held(w,A,"chime_herb")==a_herb-herb_needed and held(w,A,"blue_dye")==4,"completion takes only the remainder (dye untouched)")
	expect(w.state.events.size()==events_before+1 and w.state.events.back()==Flower.GARDEN_EVENT,"garden event appended exactly once")
	var contributed:=0
	for t in g.contributors:contributed+=int(g.contributors[t])
	expect(contributed==int(g.given.blue_dye)+int(g.given.orange_blossom)+int(g.given.chime_herb),"contributors sum equals given total")
	near(w,B,Flower.GARDEN_CELL)
	before=snap(w)
	r=act(w,B,"flower_give",Flower.GARDEN_CELL)
	expect(not r.ok and snap(w)==before and held(w,B,"blue_dye")==3,"donation after completion fails without deducting: "+r.message)

	# --- report + memento
	near(w,B,Flower.XINGHE)
	expect(not act(w,B,"flower_report",Flower.XINGHE).ok,"B cannot report without its own shipment")
	near(w,A,Flower.XINGHE)
	var seeds_before:=held(w,A,"orange_blossom_seed")
	r=act(w,A,"flower_report",Flower.XINGHE)
	expect(r.ok and rec(w,A).complete and held(w,A,"orange_blossom_seed")==seeds_before+1,"flower_report gives the memento: "+r.message)
	expect(not act(w,A,"flower_report",Flower.XINGHE).ok,"memento only once")
	expect(Flower.phase(w.state,A)=="complete","A reaches the complete phase")

	# --- back home: buy gate, sell/ship rejections, home planting, cookie
	near(w,A,Flower.TRANSFER)
	expect(act(w,A,"transit",Flower.TRANSFER,"home").ok and w.player_region(A)=="home","A returns home")
	near(w,B,Flower.TRANSFER)
	expect(act(w,B,"transit",Flower.TRANSFER,"home").ok,"B returns home")
	near(w,B,STALL)
	coins=int(w.state.players[B].coins)
	before=snap(w)
	r=act(w,B,"buy",STALL,"bluebell")
	expect(not r.ok and r.message==HOME_SEED and snap(w)==before,"home stall refuses flower seeds before chapter 3: "+r.message)
	expect(act(w,B,"buy",STALL,"radish").ok,"other seeds still sold")
	near(w,A,STALL)
	coins=int(w.state.players[A].coins)
	var seed_count:=held(w,A,"bluebell_seed")
	r=act(w,A,"buy",STALL,"bluebell")
	expect(r.ok and held(w,A,"bluebell_seed")==seed_count+1 and int(w.state.players[A].coins)==coins-28,"completed player buys flower seeds at home: "+r.message)
	for id in NOT_SELLABLE:
		before=snap(w)
		r=act(w,A,"sell",STALL,id)
		expect(not r.ok and snap(w)==before,"stall refuses to buy %s: %s"%[id,r.message])
		var ship_extra:=JSON.stringify([[[id,1]],40])
		r=act(w,A,"ship",Shipping.cell_for(w.state),ship_extra)
		expect(not r.ok and snap(w)==before,"shipping box refuses %s: %s"%[id,r.message])
	# home planting under normal rules (no chapter progress written)
	var record_b:=rec(w,B)
	var plot:=free_home_cell(w,[])
	expect(plot.x>=0,"found a free home cell")
	near(w,B,plot)
	pose(w,B,Vector2(plot)+Vector2(0.5,0.5))
	r=act(w,B,"hoe",plot)
	expect(r.ok,"B hoes at home: "+r.message)
	r=act(w,B,"seed",plot,"orange_blossom")
	expect(r.ok and w.state.crops[World.key(plot)].kind=="orange_blossom","flower seed planted at home without chapter progress: "+r.message)
	expect(rec(w,B)==record_b,"home planting writes no chapter-3 progress")
	# garden_cookie through the stove: collection accepts the new meal
	var stove:=free_home_cell(w,[plot])
	pose(w,A,Vector2(stove)+Vector2(0.5,1.5))
	inv(w,A).wood=40;inv(w,A).stone=40 # FIXTURE stove materials
	r=act(w,A,"build",stove,"stove")
	expect(r.ok,"A builds a stove: "+r.message)
	inv(w,A).flour=1 # FIXTURE flour (mill is gated behind the public kitchen)
	inv(w,A).chime_herb=held(w,A,"chime_herb")+1
	r=act(w,A,"cook",stove,"garden_cookie")
	expect(r.ok,"cook garden_cookie: "+r.message)
	expect(w.step(60.0,true),"step 60 s")
	var cookies:=held(w,A,"garden_cookie")
	r=act(w,A,"claim_cook",stove)
	expect(r.ok and held(w,A,"garden_cookie")==cookies+4 and w.state.players[A].collection.meals.has("garden_cookie"),"garden_cookie +4 and recorded in the meal collection")
	near(w,A,STALL)
	coins=int(w.state.players[A].coins)
	r=act(w,A,"sell",STALL,"garden_cookie")
	expect(r.ok and int(w.state.players[A].coins)==coins+36*(cookies+4),"garden_cookie sells at 36")

	# --- persisted world reloads through SaveSchema with everything intact
	expect(w.save(),"final save")
	var loaded=World.new()
	expect(loaded.load_world(w.save_path),"saved flower world reloads")
	if loaded.state.has("flower_nursery"):
		expect(JSON.stringify(loaded.state.flower_nursery)==JSON.stringify(w.state.flower_nursery),"flower_nursery survives reload")
		# Existing SaveSchema normalizes freshly hoed empty plots with remaining=0.
		# Compare all persisted fields after that specific legacy normalization.
		var expected_crops:Dictionary=tianwei_crops(w).duplicate(true)
		for saved_plot in expected_crops.values():
			if not saved_plot.has("remaining"):
				expect(saved_plot.kind=="","only freshly hoed empty plots omit remaining")
				saved_plot.remaining=0
		expect(json_same(loaded.state.regions[Flower.REGION].crops,expected_crops),"tianwei beds survive reload")
		expect(json_same(loaded.state.players[A].collection,w.state.players[A].collection),"flower/cookie collection survives reload")

## Equal after one JSON round trip (JSON stores every number as a float).
func json_same(a,b) -> bool:
	return JSON.stringify(JSON.parse_string(JSON.stringify(a)))==JSON.stringify(JSON.parse_string(JSON.stringify(b)))

# ------------------------------------------------------------------ rain

func test_rain() -> void:
	var w=new_world("rain")
	w.add_player(A,"Alice")
	w.state.picnic=true # FIXTURE
	unlock(w,A)
	near(w,A,STALL)
	expect(act(w,A,"flower_letter",STALL).ok,"rain: letter")
	at_yingge(w,A)
	expect(act(w,A,"transit",YINGGE_TRANSFER,Flower.REGION).ok,"rain: travel")
	near(w,A,Flower.FARMER)
	expect(act(w,A,"flower_intro",Flower.FARMER).ok,"rain: intro")
	var c:=bed(3,1)
	near(w,A,c)
	expect(act(w,A,"hoe",c).ok and act(w,A,"seed",c,"bluebell").ok,"rain: unwatered bluebell bed")
	var key:=World.key(c)
	# Day 1 sunny, day 2 cloudy: the bed stays dry and does not grow.
	while Weather.day_index(w.state.time)<2.0:
		expect(w.step(120.0,true),"rain: step")
		if Weather.day_index(w.state.time)<2.0:
			expect(not tianwei_crops(w)[key].wet and float(tianwei_crops(w)[key].growth)==0.0,"rain: dry before the rainy day")
	expect(Weather.rains(Weather.day_index(w.state.time),Flower.REGION),"rain: day 3 is rainy in Tianwei")
	expect(w.step(30.0,true),"rain: step on the rainy day")
	expect(tianwei_crops(w)[key].wet==true and float(tianwei_crops(w)[key].growth)>0.0,"rain wets the outdoor Tianwei bed and it grows")
