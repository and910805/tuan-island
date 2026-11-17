extends SceneTree
## T071 regression suite for res://scripts/market_stall.gd and its World,
## SaveSchema and Session integration: picnic gate, region/cell/reach gates,
## every action's rejection leaving state byte-identical, stock/take round trip,
## once-per-day opening, deterministic settlement for 1/2/3/8 stalls and all
## three themes, offline players, multi-day jumps, coin caps, collect, request
## replay, save/reload, schema tampering, per-player independence, stall cell
## terrain rules and reservation, no buy->stall arbitrage and snapshot privacy.
##
## PRESET (written straight into world state, not earned): state.picnic,
## state.time, player positions, inventories, coins and some market records
## (only for the cap/tamper cases). Everything else goes through World.act and
## World.step.
const World=preload("res://scripts/world.gd")
const Market=preload("res://scripts/market_stall.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const Village=preload("res://scripts/village.gd")
const Session=preload("res://scripts/session.gd")
const VillagePreview=preload("res://scripts/village_preview_art.gd")
const DAY:=1440.0
const PRIVATE_A:="market-private-alpha-token"
const PRIVATE_B:="market-private-beta-token"
const VIEW_KEYS:=["day","next_theme","open","pending","prices","report","stalls_today","stock","stock_count","theme","till","total","unlocked","visitors_estimate"]
var checks:=0
var failures:=0
var serial:=0
var _cleanup:Array[String]=[]

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func finish()->void:
	for file in _cleanup:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(file+suffix):DirAccess.remove_absolute(file+suffix)
	print("MARKET_STALL_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

static func temp_path(tag:String)->String:
	return OS.get_environment("TEMP").path_join("market-stall-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(8).hex_encode()])

static func pl(w,token:String)->Dictionary:
	var p:Dictionary=w.state.players[token]
	return p

static func msg(r:Dictionary)->String:
	return str(r.get("message",""))

static func stall(w)->Vector2i:
	var state:Dictionary=w.state
	return Market.cell_for(state)

## Stands the player one tile below `cell` (distance 1 from the cell centre).
static func stand(w,token:String,cell:Vector2i)->void:
	var p:Dictionary=pl(w,token)
	p.x=float(cell.x)+0.5
	p.y=float(cell.y)+1.5

static func market_of(w,token:String)->Dictionary:
	var p:Dictionary=pl(w,token)
	var m:Variant=p.get("market")
	if m is Dictionary:
		var copy:Dictionary=m
		return copy
	return {}

static func view(w,token:String)->Dictionary:
	var v:Dictionary=w.market_view(token)
	return v

## Recursively canonicalizes JSON-ish data: sorted String keys, whole floats as ints.
static func canon(value:Variant)->Variant:
	if value is Dictionary:
		var keys:Array=[]
		for k in value:keys.append(str(k))
		keys.sort()
		var out:={}
		for k:String in keys:
			var source:Variant=value[k] if value.has(k) else value[StringName(k)]
			out[k]=canon(source)
		return out
	if value is Array:
		var list:=[]
		for item in value:list.append(canon(item))
		return list
	if value is float and is_finite(value) and floorf(value)==value:return int(value)
	return value

static func same(a:Variant,b:Variant)->bool:
	return var_to_bytes(canon(a))==var_to_bytes(canon(b))

func act(w,token:String,action:String,cell:Vector2i,extra:String="",request:String="")->Dictionary:
	serial+=1
	var id:String=request if not request.is_empty() else "market-req-%d"%serial
	var r:Dictionary=w.act(token,id,action,cell,extra)
	return r

func write_fixture(path:String,data:Dictionary)->bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

## A rejected action leaves the whole world state byte-identical.
func expect_rejected(w,token:String,action:String,cell:Vector2i,extra:String,label:String,expected:String="")->void:
	var before:PackedByteArray=var_to_bytes(w.state)
	var had:bool=pl(w,token).has("market")
	var r:Dictionary=act(w,token,action,cell,extra)
	expect(not bool(r.get("ok",true)),label+": rejected")
	expect(not msg(r).is_empty(),label+": rejection explains itself ("+msg(r)+")")
	if not expected.is_empty():expect(msg(r)==expected,label+": message is '%s' (got '%s')"%[expected,msg(r)])
	expect(var_to_bytes(w.state)==before,label+": world state byte-identical")
	expect(pl(w,token).has("market")==had,label+": no market record invented")

## A picnic-done world (PRESET) at world day `day_index`, with players standing
## below the stall and a stocked inventory.
func make_world(tokens:Array,day_index:int=0,picnic:bool=true)->World:
	var w:=World.new()
	for token:String in tokens:w.add_player(token,token.left(6))
	w.state.picnic=picnic
	w.state.time=DAY*day_index+120.0
	var cell:=Market.CANDIDATES[0] as Vector2i
	for token:String in tokens:
		stand(w,token,cell)
		var inv:Dictionary=pl(w,token).inventory
		for item in ["radish","carrot","soup","salad","bluebell","chime_herb","egg","carp"]:inv[item]=20
		inv.radish_seed=5
		inv.wood=12
	return w

func _initialize()->void:
	run.call_deferred()

func run()->void:
	test_rules()
	test_cells()
	test_locked()
	test_gates()
	test_stock_take()
	test_open_and_view()
	test_settlement_counts()
	test_quality_stock()
	test_ranch_products()
	test_theme_ordering()
	test_multi_day_and_offline()
	test_caps()
	test_collect_and_replay()
	test_two_players()
	test_arbitrage()
	test_save_reload_and_schema()
	await test_snapshot_privacy()
	finish()

# 1. Pure rules: categories, prices, visitors, themes.
func test_rules()->void:
	var prices:Dictionary=World.SHIPPING.prices(World.CROPS,World.FISH,World.OTHER_SALES,true)
	expect(Market.sale_prices()==prices,"sale_prices equals the shipping price table")
	expect(Market.ACTIONS==["market_stock","market_take","market_open","market_collect"],"Four market actions")
	expect(Market.MAX_KINDS==4 and Market.MAX_STOCK==12,"Limits are 4 kinds / 12 pieces")
	expect(Market.CATEGORY_NAMES=={"produce":"農漁產","dish":"料理","flower":"花"},"Category names")
	expect(Market.THEMES==["produce","dish","flower"],"Theme rotation")
	for d in range(-3,9):expect(Market.theme_of(d)==Market.THEMES[posmod(d,3)],"theme_of(%d)"%d)
	var expected_visitors:={1:8,2:5,3:4,4:3,5:2,6:2,7:2,8:1,9:1,20:1}
	for n:int in expected_visitors:expect(Market.visitors_for(n)==int(expected_visitors[n]),"visitors_for(%d)==%d"%[n,int(expected_visitors[n])])
	expect(Market.visitors_for(0)==8,"visitors_for(0) is treated as one stall")
	# Categories.
	expect(Market.category_of("radish")=="produce" and Market.category_of("carp")=="produce" and Market.category_of("egg")=="produce","Crops, fish and eggs are produce")
	expect(Market.category_of("milk")=="produce" and Market.category_of("wool")=="produce","Milk and wool join the farm-products theme")
	expect(Market.category_of("cotton")=="produce","Cotton (a fibre crop) is produce, not a flower")
	for flower in ["bluebell","orange_blossom","chime_herb"]:expect(Market.category_of(flower)=="flower","%s is a flower"%flower)
	for dish:String in World.OTHER_SALES:
		if World.CROP_CATALOG.base_kind(dish) in Market.PRODUCE_EXTRA:continue
		expect(Market.category_of(dish)=="dish","%s is a dish"%dish)
	for raw in ["wood","stone","fiber","resin","sapling","plank","sprinkler_kit","tea_light","sea_salt","sugar","blue_dye",""]:
		expect(Market.category_of(raw)=="" and not Market.sellable(raw),"%s is not sellable"%raw)
	for crop:String in World.CROPS:
		expect(not Market.sellable(crop+"_seed"),"%s_seed is never sellable"%crop)
	var items:Array=Market.sellable_items()
	expect(items.size()==2*World.CROPS.size()+World.FISH.size()+World.OTHER_SALES.size(),"Both crop grades, fish and other goods are sellable (%d)"%items.size())
	for item:String in items:expect(prices.has(item) and int(prices[item])>=1,"%s has a shipping price"%item)
	# Price arithmetic (integer ceil) for every sellable item and all three themes.
	for d in range(3):
		for item:String in items:
			var base:int=int(prices[item])
			var category:=Market.category_of(item)
			var price:=Market.price_for(base,category,d)
			var factor:=13 if category==Market.theme_of(d) else 11
			expect(price*10>=base*factor and (price-1)*10<base*factor,"day %d %s: %d = ceil(%d x %d/10)"%[d,item,price,base,factor])
	expect(Market.price_for(24,"produce",0)==32 and Market.price_for(24,"produce",1)==27,"radish 24 -> 32 themed / 27 plain")
	expect(Market.price_for(32,"dish",1)==42 and Market.price_for(32,"dish",0)==36,"soup 32 -> 42 themed / 36 plain")
	expect(Market.price_for(28,"flower",2)==37 and Market.price_for(28,"flower",0)==31,"bluebell 28 -> 37 themed / 31 plain")
	expect(Market.price_for(10,"produce",1)==11 and Market.price_for(10,"produce",0)==13,"base 10 -> 11 / 13 exactly (no float drift)")
	expect(Market.day(0.0)==0 and Market.day(DAY-0.01)==0 and Market.day(DAY)==1 and Market.day(DAY*5+3)==5,"Day boundaries follow WEATHER.DAY_SECONDS")
	expect(Market.day(DAY*7+9)==Bond.day(DAY*7+9),"Same day definition as RESIDENT_BOND.day")
	expect(Market.parse("radish:3").ok and not Market.parse("radish:0").ok and not Market.parse("radish:+3").ok and not Market.parse("radish:03").ok and not Market.parse("radish").ok and not Market.parse(":3").ok and not Market.parse("radish:3:1").ok and not Market.parse("radish:13").ok,"parse accepts only item:1..12")

## Every fixed home landmark the stall must neither stand on nor touch.
static func home_landmarks()->Dictionary:
	var marks:Dictionary={}
	for npc:String in Village.NPCS:
		if str(Village.NPCS[npc].get("region","home"))=="home":marks["npc "+npc]=Village.NPCS[npc].cell
	for npc:String in Village.FESTIVAL_SPOTS:marks["festival spot "+npc]=Village.FESTIVAL_SPOTS[npc]
	for cell:Vector2i in World.Festival.VISITORS:marks["festival visitor "+str(World.Festival.VISITORS[cell])]=cell
	for index in range(World.Festival.STOPS.size()):marks["festival stop %d"%index]=World.Festival.STOPS[index]
	marks["wind-chime tree"]=World.Festival.TREE_CELL
	marks["notice board"]=Vector2i(40,29)
	marks["seed shop"]=Vector2i(43,29)
	marks["chapter starter"]=World.CHAPTER_ONE.STARTER_CELL
	for index in range(World.SHIPPING.CANDIDATES.size()):marks["shipping candidate %d"%index]=World.SHIPPING.CANDIDATES[index]
	for index in range(World.COMMUNITY.CANDIDATES.size()):marks["community table candidate %d"%index]=World.COMMUNITY.CANDIDATES[index]
	for animal:String in World.LIVESTOCK.ANIMALS:
		marks["livestock "+animal]=World.LIVESTOCK.ANIMALS[animal].cell
		marks["livestock collector "+animal]=World.LIVESTOCK.collector_cell(animal)
	for index in range(Bond.RANCH_CELLS.size()):marks["ranch cell %d"%index]=Bond.RANCH_CELLS[index]
	for index in range(Bond.DOCK_CELLS.size()):marks["dock cell %d"%index]=Bond.DOCK_CELLS[index]
	for index in range(Bond.POST_CELLS.size()):marks["post cell %d"%index]=Bond.POST_CELLS[index]
	for index in range(Bond.BELL_CELLS.size()):marks["bell cell %d"%index]=Bond.BELL_CELLS[index]
	var transit:Dictionary=World.TRANSIT.points(World.REGIONS.HOME)
	for point:String in transit:marks["transit "+point]=transit[point].cell
	marks["home exit"]=World.REGIONS.exit_cell(World.REGIONS.HOME)
	marks["home arrival"]=Vector2i(World.REGIONS.spawn(World.REGIONS.HOME))
	marks["player spawn"]=Vector2i(World.SPAWN)
	marks["chicken"]=Vector2i(45,34)
	marks["quarry"]=Vector2i(54,25)
	marks["copper"]=World.COPPER_CELL
	marks["east spawn building lot 40,33"]=Vector2i(40,33)
	marks["east spawn building lot 41,34"]=Vector2i(41,34)
	return marks

# 2. Stall cell terrain conditions, reservation and fallback.
func test_cells()->void:
	expect(Market.CANDIDATES==[Vector2i(36,30),Vector2i(36,29),Vector2i(36,31),Vector2i(35,30)],"Stall candidates are 36,30 36,29 36,31 35,30 in order")
	var plain:=World.new()
	var busy:=World.new()
	# PRESET: a mid-game plaza (bridge, picnic, festival story open).
	busy.state.board=true
	busy.state.picnic=true
	busy.state.festival_story_open=true
	var marks:=home_landmarks()
	var spawn_point:=Vector2(World.SPAWN)
	for cell:Vector2i in Market.CANDIDATES:
		var tag:="stall cell %s"%str(cell)
		for w in [plain,busy]:
			expect(w.is_land(cell) and not w.water(cell),tag+": land, not water")
			expect(w.resource(cell)=="",tag+": no resource on the cell")
		for spot:Vector2i in [cell,cell+Vector2i.DOWN]:
			var found:=World.base_resource(spot)
			expect(found!="tree" and found!="rock","%s: no fixed tree/rock at %s"%[tag,str(spot)])
		expect(VillagePreview.path_at(Vector2(cell)+Vector2(0.5,0.5)),tag+": on the paved plaza")
		for mark:String in marks:
			var at:Vector2i=marks[mark]
			expect(maxi(absi(cell.x-at.x),absi(cell.y-at.y))>=2,"%s is not on or touching %s %s"%[tag,mark,str(at)])
		expect(spawn_point.distance_to(Vector2(cell)+Vector2(0.5,0.5))>3.2,tag+": outside interaction range of the spawn point")
		expect(not plain.protected(cell) and not plain.blocked(cell),tag+": ordinary ground before the picnic")
	# After the picnic only the active cell is reserved (walk-blocked + protected).
	expect(stall(busy)==Vector2i(36,30) and Market.active_cell(busy.state)==Vector2i(36,30),"Active stall is the first candidate")
	expect(Market.active_cell(plain.state)==Market.NO_CELL and Market.cell_for(plain.state)==Vector2i(36,30),"Before the picnic there is no active stall")
	expect(busy.blocked(Vector2i(36,30)) and busy.protected(Vector2i(36,30)),"Active stall cell is blocked and protected")
	for cell:Vector2i in Market.CANDIDATES.slice(1):
		expect(not busy.blocked(cell) and not busy.protected(cell),"Inactive candidate %s stays ordinary"%str(cell))
	expect(World.market_cell(busy.state)==Market.cell_for(busy.state),"World.market_cell wraps cell_for")
	# A pre-picnic build on the first candidate is kept; the stall falls back.
	var w:=make_world(["bui"],0,false)
	stand(w,"bui",Vector2i(36,30))
	var built:=act(w,"bui","build",Vector2i(36,30),"lamp")
	expect(bool(built.ok),"Before the picnic a lamp can be built on 36,30 ("+msg(built)+")")
	w.state.picnic=true
	expect(stall(w)==Vector2i(36,29) and w.protected(Vector2i(36,29)) and not w.protected(Vector2i(36,30)),"Occupied first candidate: stall falls back to 36,29")
	stand(w,"bui",Vector2i(36,28))
	pl(w,"bui").inventory.wood=20
	expect_rejected(w,"bui","build",Vector2i(36,29),"lamp","Build on the active stall cell")
	var all:=World.new()
	all.state.picnic=true
	for cell:Vector2i in Market.CANDIDATES:all.state.ground[World.key(cell)]={"type":"path"}
	expect(Market.cell_for(all.state)==Market.NO_CELL and not all.protected(Vector2i(36,30)),"All candidates occupied: NO_CELL, nothing reserved")
	all.add_player("ann","ann")
	stand(all,"ann",Vector2i(36,30))
	pl(all,"ann").inventory.radish=3
	expect_rejected(all,"ann","market_stock",Vector2i(36,30),"radish:1","No free stall cell",Market.NO_STALL)

# 3. Picnic gate.
func test_locked()->void:
	var w:=make_world(["lin"],0,false)
	var cell:=stall(w)
	for pair in [["market_stock","radish:1"],["market_take","radish:1"],["market_open",""],["market_collect",""]]:
		expect_rejected(w,"lin",str(pair[0]),cell,str(pair[1]),"Before picnic "+str(pair[0]),Market.LOCKED)
	expect(not view(w,"lin").unlocked,"View says locked before the picnic")
	expect(Market.LOCKED=="完成渡口野餐後，廣場的市集攤位才會開放。","Locked message text")

# 4. Region, cell and reach gates.
func test_gates()->void:
	var w:=make_world(["gus"])
	var cell:=stall(w)
	expect_rejected(w,"gus","market_stock",Vector2i(36,29),"radish:1","Wrong cell",Market.WRONG_CELL)
	expect_rejected(w,"gus","market_stock",Vector2i(42,31),"radish:1","Shipping box instead of the stall",Market.WRONG_CELL)
	var p:Dictionary=pl(w,"gus")
	p.x=36.5
	p.y=34.5
	expect_rejected(w,"gus","market_stock",cell,"radish:1","Too far (4 tiles)",Market.TOO_FAR)
	expect_rejected(w,"gus","market_open",cell,"","Too far open",Market.TOO_FAR)
	stand(w,"gus",cell)
	p.region=World.REGIONS.LANYANG
	expect_rejected(w,"gus","market_stock",cell,"radish:1","Wrong region",Market.WRONG_REGION)
	expect_rejected(w,"gus","market_collect",cell,"","Wrong region collect",Market.WRONG_REGION)
	p.region=World.REGIONS.HOME
	expect(bool(act(w,"gus","market_stock",cell,"radish:1").ok),"Back home, below the stall, stocking works")

# 5. Stock / take and their rejections.
func test_stock_take()->void:
	var w:=make_world(["sid"])
	var cell:=stall(w)
	var inv_before:Dictionary=pl(w,"sid").inventory.duplicate(true)
	for bad in ["","radish","radish:","radish:0","radish:-1","radish:13","radish:1.5","radish:+2","radish:02",":2","radish:1:1","radish: 1"]:
		expect_rejected(w,"sid","market_stock",cell,bad,"Malformed stock '%s'"%bad)
	expect_rejected(w,"sid","market_stock",cell,"radish_seed:1","Seeds are not sellable")
	expect_rejected(w,"sid","market_stock",cell,"wood:1","Raw wood is not sellable")
	expect_rejected(w,"sid","market_stock",cell,"pumpkin:1","Not in inventory")
	expect_rejected(w,"sid","market_stock",cell,"unknown_item:1","Unknown item")
	pl(w,"sid").inventory.carrot=2
	expect_rejected(w,"sid","market_stock",cell,"carrot:3","Not enough in inventory")
	expect_rejected(w,"sid","market_take",cell,"radish:1","Take with nothing on the stall")
	expect_rejected(w,"sid","market_open",cell,"","Open an empty stall")
	expect_rejected(w,"sid","market_collect",cell,"","Collect an empty till")
	pl(w,"sid").inventory.carrot=20
	var r:=act(w,"sid","market_stock",cell,"radish:3")
	expect(bool(r.ok) and int(pl(w,"sid").inventory.radish)==17,"Stock radish 3 ("+msg(r)+")")
	expect(same(market_of(w,"sid"),{"stock":{"radish":3},"open_day":-1,"pending":false,"till":0,"total":0,"report":{}}),"Lazy record created with the stock")
	expect(bool(act(w,"sid","market_stock",cell,"radish:2").ok) and int(market_of(w,"sid").stock.radish)==5,"Stocking the same item adds up")
	expect(bool(act(w,"sid","market_stock",cell,"soup:2").ok),"Stock soup")
	expect(bool(act(w,"sid","market_stock",cell,"bluebell:2").ok),"Stock bluebell")
	expect(bool(act(w,"sid","market_stock",cell,"egg:1").ok),"Stock egg (fourth kind)")
	expect_rejected(w,"sid","market_stock",cell,"carp:1","Fifth kind")
	expect_rejected(w,"sid","market_stock",cell,"radish:3","Over twelve pieces (10+3)")
	expect(bool(act(w,"sid","market_stock",cell,"radish:2").ok) and Market.stock_count(market_of(w,"sid").stock)==12,"Exactly twelve pieces")
	expect_rejected(w,"sid","market_stock",cell,"radish:1","Full stall")
	for bad in ["radish","radish:0","soup:3","carp:1","radish:x"]:
		expect_rejected(w,"sid","market_take",cell,bad,"Take '%s'"%bad)
	# Inventory cap on take.
	var inv:Dictionary=pl(w,"sid").inventory
	var held:=int(inv.egg)
	inv.egg=Market.MAX_ITEM
	expect_rejected(w,"sid","market_take",cell,"egg:1","Take into a full inventory slot")
	inv.egg=held
	# Round trip: take everything back -> inventory exactly as before stocking.
	for pair in [["radish",7],["soup",2],["bluebell",2],["egg",1]]:
		expect(bool(act(w,"sid","market_take",cell,"%s:%d"%[pair[0],pair[1]]).ok),"Take %s %d"%[pair[0],pair[1]])
	expect(pl(w,"sid").inventory==inv_before,"Stock/take round trip restores the inventory exactly")
	expect(market_of(w,"sid").stock.is_empty() and Market.stock_count(market_of(w,"sid").stock)==0,"Stall is empty again")

# 6. Opening once per day, view shape.
func test_open_and_view()->void:
	var w:=make_world(["ola","oli"],1)
	var cell:=stall(w)
	var v:=view(w,"ola")
	var keys:Array=v.keys()
	keys.sort()
	expect(keys==VIEW_KEYS,"View has exactly the agreed keys")
	expect(v.unlocked==true and int(v.day)==1 and v.theme=="dish" and v.next_theme=="flower","Day 1: theme dish, next flower")
	expect(v.open==false and v.pending==false and int(v.stalls_today)==0 and int(v.visitors_estimate)==8,"Fresh view: closed, estimate for one stall is 8")
	expect(v.stock.is_empty() and int(v.stock_count)==0 and int(v.till)==0 and int(v.total)==0 and v.report.is_empty(),"Fresh view values")
	expect(v.prices.size()==Market.sellable_items().size(),"View prices list every sellable item")
	expect(same(v.prices.soup,{"base":32,"price":42,"category":"dish","themed":true}) and same(v.prices.radish,{"base":24,"price":27,"category":"produce","themed":false}),"Today's prices with theme flags")
	expect(not pl(w,"ola").has("market"),"Viewing does not create a record")
	expect(Market.stockable(v,"radish") and not Market.stockable(v,"wood") and not Market.stockable(v,"radish_seed"),"stockable helper")
	expect(bool(act(w,"ola","market_stock",cell,"soup:4").ok),"Ola stocks soup")
	var r:=act(w,"ola","market_open",cell,"")
	expect(bool(r.ok) and msg(r).contains("料理"),"Ola opens; message names the theme ("+msg(r)+")")
	var m:=market_of(w,"ola")
	expect(int(m.open_day)==1 and m.pending==true,"open_day=today, pending")
	expect_rejected(w,"ola","market_open",cell,"","Second open the same day","今天已經開張了，明天再來開下一輪。")
	expect_rejected(w,"ola","market_open",cell,"x","Open with extra")
	v=view(w,"ola")
	expect(v.open==true and v.pending==true and int(v.stalls_today)==1 and int(v.visitors_estimate)==8,"Open view: one stall, 8 visitors")
	var vo:=view(w,"oli")
	expect(vo.open==false and int(vo.stalls_today)==1 and int(vo.visitors_estimate)==5,"Other player sees one stall today and would get 5 visitors")
	expect(bool(act(w,"ola","market_stock",cell,"radish:2").ok),"Stocking stays allowed after opening")
	# Previous round still pending (time moved, no step yet): opening refused.
	w.state.time=float(w.state.time)+DAY
	expect_rejected(w,"ola","market_open",cell,"","Open while yesterday is unsettled")
	expect(w.step(0.5,true),"Step settles")
	expect(market_of(w,"ola").pending==false and int(market_of(w,"ola").report.day)==1,"Yesterday settled")
	expect(bool(act(w,"ola","market_open",cell,"").ok) or market_of(w,"ola").stock.is_empty(),"Next day: open again (if stock remains)")

## Opens a stall for each token with `stock` (item->count) via World.act.
func open_with(w,token:String,stock:Dictionary)->void:
	var cell:=stall(w)
	stand(w,token,cell)
	for item:String in stock:
		var r:=act(w,token,"market_stock",cell,"%s:%d"%[item,int(stock[item])])
		expect(bool(r.ok),"%s stocks %s %d (%s)"%[token,item,int(stock[item]),msg(r)])
	var o:=act(w,token,"market_open",cell,"")
	expect(bool(o.ok),"%s opens (%s)"%[token,msg(o)])

func settle_next_day(w)->void:
	w.state.time=(floorf(float(w.state.time)/DAY)+1.0)*DAY+5.0
	expect(w.step(0.5,true),"Step after midnight")

# 7. Settlement numbers for 1/2/3/8 stalls.
func test_ranch_products()->void:
	var w:=make_world(["rancher"],0)
	var seller:=pl(w,"rancher")
	seller.inventory.milk=4
	seller.inventory.wool=4
	open_with(w,"rancher",{"milk":4,"wool":4})
	settle_next_day(w)
	var report:Dictionary=market_of(w,"rancher").report
	expect(same(report.sold,{"milk":4,"wool":4}) and int(report.coins)==440,"Farm-products day sells both goods for 4×47 plus 4×63")
	var before:=int(seller.coins)
	expect(act(w,"rancher","market_collect",stall(w)).ok and int(seller.coins)-before==440,"Market pays the livestock proceeds once")

func test_settlement_counts()->void:
	# One stall, day 0 (produce): radish 3, soup 5, bluebell 4 -> 8 visitors.
	var w:=make_world(["one"],0)
	open_with(w,"one",{"radish":3,"soup":5,"bluebell":4})
	var coins_before:=int(pl(w,"one").coins)
	settle_next_day(w)
	var m:=market_of(w,"one")
	# Order radish(themed), bluebell, soup: r b s r b s r b.
	var expected_report:={"day":0,"visitors":8,"stalls":1,"theme":"produce","sold":{"radish":3,"bluebell":3,"soup":2},"coins":3*32+3*31+2*36}
	expect(same(m.report,expected_report),"1 stall: report %s"%str(m.report))
	expect(int(m.till)==261 and int(m.total)==261 and m.pending==false,"1 stall: till/total 261")
	expect(same(m.stock,{"bluebell":1,"soup":3}),"1 stall: unsold stock stays on the stall")
	expect(int(pl(w,"one").coins)==coins_before,"Settlement does not pay coins directly")
	expect(not w.step(0.5,true) or same(market_of(w,"one"),m),"A second step does not settle again")
	expect(same(market_of(w,"one").report,expected_report),"Report unchanged by another step")
	# 2, 3 and 8 stalls on day 0, each stocked with 12 radish.
	for n:int in [2,3,8]:
		var tokens:=[]
		for i in range(n):tokens.append("s%d_%d"%[n,i])
		var many:=make_world(tokens,0)
		for token:String in tokens:open_with(many,token,{"radish":12})
		expect(int(view(many,tokens[0]).stalls_today)==n,"%d stalls counted today"%n)
		settle_next_day(many)
		var per:=Market.visitors_for(n)
		for token:String in tokens:
			var mm:=market_of(many,token)
			expect(same(mm.report,{"day":0,"visitors":per,"stalls":n,"theme":"produce","sold":{"radish":per},"coins":per*32}),"%d stalls: %s report %s"%[n,token,str(mm.report)])
			expect(int(mm.stock.radish)==12-per and int(mm.till)==per*32,"%d stalls: %s keeps %d radish, till %d"%[n,token,12-per,per*32])
	expect(Market.visitors_for(2)==5 and Market.visitors_for(3)==4 and Market.visitors_for(8)==1,"2/3/8 stalls -> 5/4/1 visitors")
	# Opened but emptied stalls do not count and sell nothing.
	var e:=make_world(["full","empty"],0)
	open_with(e,"full",{"radish":12})
	open_with(e,"empty",{"soup":1})
	expect(bool(act(e,"empty","market_take",stall(e),"soup:1").ok),"Empty stall owner takes the soup back after opening")
	settle_next_day(e)
	expect(int(market_of(e,"full").report.stalls)==1 and int(market_of(e,"full").report.visitors)==8,"Only stocked stalls count")
	expect(same(market_of(e,"empty").report,{"day":0,"visitors":0,"stalls":1,"theme":"produce","sold":{},"coins":0}) and market_of(e,"empty").pending==false,"Empty pending stall settles with nothing sold")

func test_quality_stock()->void:
	var w:=make_world(["grower"],0)
	pl(w,"grower").inventory.quality_radish=2
	expect(Market.category_of("quality_bluebell")=="flower","A quality flower keeps its category")
	expect(int(view(w,"grower").prices.quality_radish.price)==39,"Produce day quotes 39 coins for a quality radish")
	open_with(w,"grower",{"quality_radish":2,"radish":1})
	expect(int(pl(w,"grower").inventory.quality_radish)==0,"Only the quality stack is moved for the two quality radishes")
	var path:=temp_path("quality")
	w.save_path=path
	expect(w.save() and w.load_world(path),"Open quality stock survives reload")
	settle_next_day(w)
	var market:=market_of(w,"grower")
	expect(same(market.report.sold,{"quality_radish":2,"radish":1}),"Settlement preserves both crop grades")
	expect(int(market.till)==110,"Two quality radishes at 39 and one regular radish at 32 settle for 110")
	expect(w.save() and w.load_world(path),"Settled quality report survives reload")
	for file:String in [path,path+".bak"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)

# 8. Theme ordering and prices for all three themes (2 stalls -> 5 visitors).
func test_theme_ordering()->void:
	var expected:={
		0:{"sold":{"radish":2,"bluebell":2,"soup":1},"coins":2*32+2*31+1*36},
		1:{"sold":{"soup":2,"bluebell":2,"radish":1},"coins":2*42+2*31+1*27},
		2:{"sold":{"bluebell":2,"radish":2,"soup":1},"coins":2*37+2*27+1*36},
	}
	for d:int in expected:
		var w:=make_world(["ta","tb"],d)
		open_with(w,"ta",{"radish":3,"soup":3,"bluebell":3})
		open_with(w,"tb",{"carp":1})
		settle_next_day(w)
		var m:=market_of(w,"ta")
		expect(same(m.report,{"day":d,"visitors":5,"stalls":2,"theme":Market.theme_of(d),"sold":expected[d].sold,"coins":expected[d].coins}),"Day %d (%s): report %s"%[d,Market.theme_of(d),str(m.report)])
		expect(int(m.till)==int(expected[d].coins),"Day %d till"%d)
		expect(same(market_of(w,"tb").report.sold,{"carp":1}),"Day %d: one-piece stall sells out and stops"%d)

# 9. Multi-day jumps, time set forward without stepping, offline players.
func test_multi_day_and_offline()->void:
	var w:=make_world(["on","off"],0)
	open_with(w,"off",{"radish":12})
	w.active_tokens.erase("off")
	# Time set forward without stepping; "on" opens on day 1 while day 0 is unsettled.
	w.state.time=DAY+10.0
	open_with(w,"on",{"soup":12})
	expect(market_of(w,"off").pending==true,"Offline stall still pending before the step")
	w.state.time=DAY*4+10.0
	expect(w.step(0.5,true),"One step after a multi-day jump")
	var off:=market_of(w,"off")
	var on:=market_of(w,"on")
	expect(off.pending==false and same(off.report,{"day":0,"visitors":8,"stalls":1,"theme":"produce","sold":{"radish":8},"coins":8*32}),"Offline player's day-0 stall settled alone: %s"%str(off.report))
	expect(on.pending==false and same(on.report,{"day":1,"visitors":8,"stalls":1,"theme":"dish","sold":{"soup":8},"coins":8*42}),"Day-1 stall settled in its own round: %s"%str(on.report))
	expect(int(off.stock.radish)==4 and int(on.stock.soup)==4,"Unsold stock remains after the jump")
	# Inactive world steps never settle.
	open_with(w,"on",{})
	w.state.time=DAY*6+10.0
	var snapshot:=var_to_bytes(w.state)
	expect(w.step(0.5,false) and var_to_bytes(w.state)==snapshot,"Paused step changes nothing")
	expect(w.step(0.5,true) and market_of(w,"on").pending==false and int(market_of(w,"on").report.day)==4,"Next active step settles day 4")

# 10. Coin caps.
func test_caps()->void:
	var w:=make_world(["cap"],0)
	open_with(w,"cap",{"radish":3})
	var m:Dictionary=pl(w,"cap").market
	m.till=World.SHIPPING.MAX_COINS-40  # PRESET
	m.total=World.SHIPPING.MAX_COINS
	settle_next_day(w)
	m=market_of(w,"cap")
	expect(int(m.till)==World.SHIPPING.MAX_COINS-8 and int(m.report.coins)==32 and same(m.report.sold,{"radish":1}),"Selling stops before the till would pass the cap")
	expect(int(m.total)==World.SHIPPING.MAX_COINS and int(m.stock.radish)==2,"Total saturates; unsold radish stays")
	var cell:=stall(w)
	pl(w,"cap").coins=10
	expect_rejected(w,"cap","market_collect",cell,"","Collect over the wallet cap","鈴幣錢包已達上限，先花掉一些再來收。")

# 11. Collect and request replay.
func test_collect_and_replay()->void:
	var w:=make_world(["col"],0)
	var cell:=stall(w)
	var inv:Dictionary=pl(w,"col").inventory
	var r:=act(w,"col","market_stock",cell,"radish:4","replay-stock")
	expect(bool(r.ok) and int(inv.radish)==16,"Stock with a fixed request id")
	var again:=act(w,"col","market_stock",cell,"radish:4","replay-stock")
	expect(again==r and int(pl(w,"col").inventory.radish)==16 and int(market_of(w,"col").stock.radish)==4,"Replayed stock returns the receipt and moves nothing")
	expect(bool(act(w,"col","market_open",cell,"","replay-open").ok),"Open")
	settle_next_day(w)
	var till:=int(market_of(w,"col").till)
	expect(till==4*32,"Till holds 4 radish at 32")
	var coins:=int(pl(w,"col").coins)
	var c:=act(w,"col","market_collect",cell,"","replay-collect")
	expect(bool(c.ok) and int(pl(w,"col").coins)==coins+till and int(market_of(w,"col").till)==0 and int(market_of(w,"col").total)==till,"Collect moves the till to coins; total unchanged")
	var c2:=act(w,"col","market_collect",cell,"","replay-collect")
	expect(c2==c and int(pl(w,"col").coins)==coins+till,"Replayed collect does not pay twice")
	expect_rejected(w,"col","market_collect",cell,"","Collect again with an empty till")
	expect_rejected(w,"col","market_collect",cell,"x","Collect with extra")
	var reopen:=act(w,"col","market_open",cell,"","replay-open")
	expect(reopen==act(w,"col","market_open",cell,"","replay-open") and int(market_of(w,"col").open_day)==0,"Replayed open id from yesterday returns yesterday's receipt")

# 12. Two players are independent.
func test_two_players()->void:
	var w:=make_world(["ann","bob"],2)
	var cell:=stall(w)
	open_with(w,"ann",{"bluebell":6})
	expect(not pl(w,"bob").has("market") and view(w,"bob").stock.is_empty(),"Bob has no record and sees no stock")
	expect_rejected(w,"bob","market_take",cell,"bluebell:1","Bob cannot take Ann's stock")
	expect(bool(act(w,"bob","market_stock",cell,"chime_herb:2").ok),"Bob stocks his own chime herb")
	expect(same(market_of(w,"ann").stock,{"bluebell":6}) and same(market_of(w,"bob").stock,{"chime_herb":2}),"Separate stocks")
	settle_next_day(w)
	expect(int(market_of(w,"ann").report.stalls)==1 and int(market_of(w,"ann").till)==6*37,"Ann settles alone (Bob never opened): 6 bluebell at 37")
	expect(market_of(w,"bob").report.is_empty() and int(market_of(w,"bob").till)==0,"Bob untouched")

# 13. No buy -> stall arbitrage; seeds never sellable.
func test_arbitrage()->void:
	var w:=make_world(["arb"],0)
	var p:Dictionary=pl(w,"arb")
	var shop:=Vector2i(43,29)
	p.x=43.5
	p.y=30.5
	var prices:=Market.sale_prices()
	for item:String in Market.sellable_items():
		var best:=0
		for d in range(3):best=maxi(best,Market.price_for(int(prices[item]),Market.category_of(item),d))
		p.coins=100000
		var held:=int(p.inventory.get(item,0))
		var r:=act(w,"arb","buy",shop,item)
		var spent:=100000-int(p.coins)
		var gained:=int(p.inventory.get(item,0))-held
		expect(gained<=0 or spent>gained*best,"%s cannot be bought for <= its best market price %d (gained %d, spent %d)"%[item,best,gained,spent])
		if bool(r.ok):expect(gained<=0 and not Market.sellable(item+"_seed"),"Buying %s yields an unsellable seed, not the item"%item)
	p.coins=1000
	var held_sapling:=int(p.inventory.get("sapling",0))
	expect(bool(act(w,"arb","buy",shop,"sapling").ok) and int(p.inventory.sapling)==held_sapling+1,"Saplings are buyable")
	expect(not Market.sellable("sapling"),"…but saplings are not sellable")
	var cell:=stall(w)
	stand(w,"arb",cell)
	p.inventory.radish_seed=5
	expect_rejected(w,"arb","market_stock",cell,"radish_seed:1","Seeds rejected at the stall")
	expect_rejected(w,"arb","market_stock",cell,"sapling:1","Saplings rejected at the stall")

static func tampered(good:Dictionary,label:String,today:int)->Dictionary:
	var m:Dictionary=good.duplicate(true)
	var report:Dictionary=m.report
	match label:
		"unsellable seed in stock":m.stock={"radish_seed":1}
		"raw wood in stock":m.stock={"wood":1}
		"unknown item in stock":m.stock={"gold_bar":1}
		"thirteen pieces":m.stock={"radish":7,"soup":6}
		"five kinds":m.stock={"radish":1,"soup":1,"egg":1,"carp":1,"salad":1}
		"zero count entry":m.stock={"radish":0}
		"fractional count":m.stock={"radish":1.5}
		"string count":m.stock={"radish":"2"}
		"open_day in the future":m.open_day=today+1
		"open_day below -1":m.open_day=-2
		"pending without opening":
			m.open_day=-1
			m.pending=true
			m.report={}
		"pending not bool":m.pending=1
		"negative till":m.till=-1
		"till over cap":
			m.till=World.SHIPPING.MAX_COINS+1
			m.total=World.SHIPPING.MAX_COINS+1
		"till above total":m.till=int(m.total)+1
		"extra field":m.mood=1
		"missing field":m.erase("total")
		"report wrong theme":report.theme="flower"
		"report day after open_day":report.day=int(m.open_day)+1
		"report missing coins":report.erase("coins")
		"report sold more than visitors":
			report.sold={"radish":9}
			report.visitors=8
		"report sold seed":report.sold={"radish_seed":1}
		"report visitors 9":report.visitors=9
		"stock not a dictionary":m.stock=[]
		"report not a dictionary":m.report=[]
	return m

# 14. Save -> reload equality, legacy saves, schema tampering.
func test_save_reload_and_schema()->void:
	var path:=temp_path("world")
	var fixture:=temp_path("fixture")
	_cleanup.append(path)
	_cleanup.append(fixture)
	var w:=make_world(["sam","tia"],0)
	w.save_path=path
	open_with(w,"sam",{"radish":5,"soup":3})
	settle_next_day(w)
	open_with(w,"sam",{"bluebell":2})
	expect(bool(act(w,"tia","market_stock",stall(w),"egg:2").ok),"Tia stocks without opening")
	expect(w.save(),"World saves")
	var restored:=World.new()
	expect(restored.load_world(path),"Fresh world reloads the save")
	if failures>0:return
	for token in ["sam","tia"]:
		expect(same(market_of(restored,token),market_of(w,token)),"%s market survives reload (canonical bytes)"%token)
		expect(same(pl(restored,token).inventory,pl(w,token).inventory) and int(pl(restored,token).coins)==int(pl(w,token).coins),"%s inventory and coins survive reload"%token)
		expect(same(view(restored,token),view(w,token)),"%s view identical after reload"%token)
	var sm:=market_of(restored,"sam")
	expect(typeof(sm.till)==TYPE_INT and typeof(sm.open_day)==TYPE_INT and typeof(sm.stock.values()[0])==TYPE_INT and typeof(sm.report.day)==TYPE_INT and typeof(sm.report.sold.values()[0])==TYPE_INT,"Validation normalizes reloaded numbers to ints")
	settle_next_day(restored)
	expect(market_of(restored,"sam").pending==false and int(market_of(restored,"sam").report.day)==1,"Reloaded pending stall settles on the next step")
	# Legacy save without the field.
	var base:Dictionary=w.state.duplicate(true)
	var old:Dictionary=base.duplicate(true)
	for token in ["sam","tia"]:(old.players[token] as Dictionary).erase("market")
	expect(write_fixture(fixture,old),"Write legacy fixture")
	var legacy:=World.new()
	expect(legacy.load_world(fixture),"Save without market loads")
	expect(not pl(legacy,"sam").has("market") and not pl(legacy,"tia").has("market"),"Loading does not invent a market key")
	expect(write_fixture(fixture,base),"Write control fixture")
	var control:=World.new()
	expect(control.load_world(fixture) and same(market_of(control,"sam"),market_of(w,"sam")),"Control fixture loads")
	if failures>0:return
	var today:=Market.day(float(base.time))
	var good:Dictionary=market_of(w,"sam").duplicate(true)
	var tampers:Array=[]
	var labels:=["unsellable seed in stock","raw wood in stock","unknown item in stock","thirteen pieces","five kinds",
		"zero count entry","fractional count","string count","open_day in the future","open_day below -1",
		"pending without opening","pending not bool","negative till","till over cap","till above total",
		"extra field","missing field","report wrong theme","report day after open_day","report missing coins",
		"report sold more than visitors","report sold seed","report visitors 9","stock not a dictionary","report not a dictionary"]
	for label:String in labels:tampers.append([label,tampered(good,label,today)])
	tampers.append(["market is an array",[]])
	tampers.append(["market is a string","stall"])
	tampers.append(["market is null",null])
	var probe:=World.new()
	var pristine:Dictionary=probe.state.duplicate(true)
	expect(tampers.size()>=8,"At least eight tamper cases (%d)"%tampers.size())
	for tamper:Array in tampers:
		var bad:Dictionary=base.duplicate(true)
		(bad.players.sam as Dictionary).market=tamper[1]
		expect(write_fixture(fixture,bad),"Write tampered fixture: "+str(tamper[0]))
		expect(not probe.load_world(fixture),"Schema rejects "+str(tamper[0]))
		expect(probe.state==pristine,"Rejected load leaves the world untouched: "+str(tamper[0]))
	expect(not Market.valid(good,float(base.time)-DAY*2,{}),"A record from the future (relative to world time) is rejected")
	expect(Market.valid(good.duplicate(true),float(base.time),{}),"The untouched record is valid")

# 15. Snapshot privacy.
func test_snapshot_privacy()->void:
	var session:=Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=make_world([PRIVATE_A,PRIVATE_B],0)
	var w=session.world
	open_with(w,PRIVATE_A,{"radish":4})
	settle_next_day(w)
	expect(bool(act(w,PRIVATE_B,"market_stock",stall(w),"soup:3").ok),"Beta stocks soup")
	session.peers={1:PRIVATE_A,2:PRIVATE_B}
	for region in World.REGIONS.ALL:
		var public:Dictionary=session.public_state(region)
		if public.is_empty():continue
		var clean:=true
		for id in public.get("players",{}):
			if (public.players[id] as Dictionary).has("market"):clean=false
		expect(clean,"public_state(%s) has no player market"%region)
		var text:=JSON.stringify(public)
		expect(not text.contains("open_day") and not text.contains("\"till\""),"public_state(%s) carries no stall records"%region)
	expect(pl(w,PRIVATE_A).has("market"),"Publishing does not strip the live record")
	session._send_snapshot(1)
	var snap:Dictionary=session.snapshot
	expect(snap.has("own_market"),"Recipient snapshot has own_market")
	var own:Dictionary=snap.get("own_market",{})
	expect(same(own,w.market_view(PRIVATE_A)),"own_market equals the recipient's own view")
	expect(not same(own,w.market_view(PRIVATE_B)),"own_market is not the other player's view")
	expect(int(own.till)==4*32 and same(own.report.sold,{"radish":4}),"Own report and till visible to the owner")
	expect(not JSON.stringify(snap.get("players",{})).contains("open_day"),"Snapshot players carry no market records")
	expect(own.stock.is_empty() and int(own.stock_count)==0,"Alpha's own_market does not show Beta's stocked soup")
	session.world=null
	session.queue_free()
	await process_frame
