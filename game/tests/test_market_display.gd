extends SceneTree
## T071 regression suite for res://scripts/market_display.gd (「攤位布置」): the
## presentation only stall tags for the player's own stocked goods and the
## 「客人的話」 remark. Pure functions (constants, shelf, themed_items, remark,
## remark_line) plus a real World integration that feeds World.market_view(token)
## into shelf/remark and proves they never write world state.
##
## PRESET (written straight into world state, not earned, same presets as
## test_market_visitors.gd / test_market_stall.gd): state.picnic (false at first,
## then set true), state.time (start of world day 1, later moved to one second
## before the next midnight), player positions (standing one tile below the stall
## cell) and player inventories (stocked with sellable goods). Each World also
## gets a temp save_path that is removed at the end. The unit-test market views
## are hand-built dictionaries (make_view), not produced by the game.
## REALLY EXERCISED: market_stock / market_open / market_take via World.act, the
## midnight settlement via World.step (real 0.5 s ticks across midnight),
## World.market_view, and every public function of market_display.gd.
const World=preload("res://scripts/world.gd")
const Market=preload("res://scripts/market_stall.gd")
const MD=preload("res://scripts/market_display.gd")
const DAY:=1440.0
const ENTRY_KEYS:=["count","item","offset","slot","themed"]
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
	print("MARKET_DISPLAY checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

static func temp_path(tag:String)->String:
	return OS.get_environment("TEMP").path_join("market-display-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(8).hex_encode()])

static func pl(w,token:String)->Dictionary:
	var p:Dictionary=w.state.players[token]
	return p

static func stall(w)->Vector2i:
	var state:Dictionary=w.state
	return Market.cell_for(state)

static func stand(w,token:String,cell:Vector2i)->void:
	var p:Dictionary=pl(w,token)
	p.x=float(cell.x)+0.5
	p.y=float(cell.y)+1.5

static func view(w,token:String)->Dictionary:
	var v:Dictionary=w.market_view(token)
	return v

static func now_of(w)->float:
	return float(w.state.time)

func act(w,token:String,action:String,cell:Vector2i,extra:String="")->Dictionary:
	serial+=1
	var r:Dictionary=w.act(token,"display-req-%d"%serial,action,cell,extra)
	return r

## Picnic flag, time, positions and inventories are PRESET exactly like test_market_visitors.gd.
func make_world(tokens:Array,day_index:int,picnic:bool)->World:
	var w:=World.new()
	var path:=temp_path("world")
	_cleanup.append(path)
	w.save_path=path
	for token:String in tokens:w.add_player(token,token.left(6))
	w.state.picnic=picnic
	w.state.time=DAY*day_index+120.0
	var cell:=Market.CANDIDATES[0] as Vector2i
	for token:String in tokens:
		stand(w,token,cell)
		var inv:Dictionary=pl(w,token).inventory
		for item in ["radish","carrot","soup","salad","bluebell","chime_herb","egg","carp"]:inv[item]=20
	return w

## Hand-built view with the same keys as Market.view (world day 4: dish). No
## "prices" key unless given, so themed falls back to Market.category_of.
static func make_view(over:Dictionary)->Dictionary:
	var v:={"unlocked":true,"day":4,"theme":"dish","next_theme":"flower","open":false,"pending":false,
		"stalls_today":0,"visitors_estimate":8,"stock":{},"stock_count":0,"till":0,"total":0,"report":{}}
	for key in over:v[key]=over[key]
	return v

static func items_of(entries:Array)->Array:
	var result:=[]
	for entry in entries:
		if entry is Dictionary:result.append((entry as Dictionary).get("item"))
	return result

func _initialize()->void:
	run.call_deferred()

func run()->void:
	test_constants()
	test_shelf_garbage()
	test_shelf_shapes()
	test_themed_items()
	test_remark()
	test_world_integration()
	finish()

# 1. Constants.
func test_constants()->void:
	expect(MD.TAG==Vector2(12,12),"TAG is 12x12 (%s)"%str(MD.TAG))
	expect(MD.TAG.x>0.0 and MD.TAG.y>0.0,"TAG has positive size")
	expect(MD.SLOTS.size()==Market.MAX_KINDS,"SLOTS count %d == Market.MAX_KINDS %d"%[MD.SLOTS.size(),Market.MAX_KINDS])
	expect(MD.VARIETY_KINDS==3,"VARIETY_KINDS is 3")
	var image:=Rect2(Vector2.ZERO,Vector2(64,64))
	for i in range(MD.SLOTS.size()):
		expect(typeof(MD.SLOTS[i])==TYPE_VECTOR2,"Slot %d is a Vector2"%i)
		var offset:Vector2=MD.SLOTS[i]
		var tag:=Rect2(offset,MD.TAG)
		expect(image.encloses(tag),"Tag %d %s lies inside the 64x64 stall image"%[i,str(tag)])
		for j in range(i+1,MD.SLOTS.size()):
			var other_offset:Vector2=MD.SLOTS[j]
			expect(not tag.intersects(Rect2(other_offset,MD.TAG)),"Tags %d and %d do not overlap"%[i,j])
	for text:String in [MD.REMARK_PREFIX,MD.REMARK_NOTE,MD.REMARK_CLOSED,MD.REMARK_EMPTY,MD.REMARK_VARIETY]:
		expect(not text.is_empty(),"Remark constant is not empty: "+text)
	expect(MD.REMARK_THEMED.count("%s")==2 and MD.REMARK_OTHER.count("%s")==2,"Themed/other formats take two strings")

# 2a. shelf() on garbage input.
func test_shelf_garbage()->void:
	expect(MD.shelf({}).is_empty(),"Empty view -> empty shelf")
	expect(MD.shelf({"stock":{"radish":3}}).is_empty(),"Missing unlocked -> empty shelf")
	expect(MD.shelf(make_view({"unlocked":false,"stock":{"radish":3}})).is_empty(),"Locked -> empty shelf")
	expect(MD.shelf(make_view({"stock":{}})).is_empty(),"Empty stock -> empty shelf")
	for garbage in [null,"radish:3",[],["radish"],3,Vector2(1,1)]:
		expect(MD.shelf(make_view({"stock":garbage})).is_empty(),"Stock %s -> empty shelf"%var_to_str(garbage))
	var mixed:={5:3,"":2,&"carrot":4,"radish":0,"egg":-2,"carp":"3","soup":null,"salad":[1],"bluebell":0.5,"chime_herb":2}
	var filtered:Array=MD.shelf(make_view({"stock":mixed}))
	expect(items_of(filtered)==["chime_herb"],"Non-string keys, empty key, zero/negative/non-numeric/fractional<1 counts are dropped: %s"%str(items_of(filtered)))
	var floats:Array=MD.shelf(make_view({"stock":{"radish":2.0,"soup":2.7}}))
	expect(floats.size()==2,"Float counts kept (%d)"%floats.size())
	if floats.size()==2:
		var r:Dictionary=floats[0]
		var s:Dictionary=floats[1]
		expect(r.item=="radish" and typeof(r.count)==TYPE_INT and int(r.count)==2,"Float 2.0 -> int 2")
		expect(s.item=="soup" and typeof(s.count)==TYPE_INT and int(s.count)==2,"Float 2.7 -> int 2 (truncated)")

func check_shelf(entries:Array,label:String)->void:
	var last:=""
	for i in range(entries.size()):
		expect(entries[i] is Dictionary,label+": entry %d is a dictionary"%i)
		if not entries[i] is Dictionary:continue
		var entry:Dictionary=entries[i]
		var keys:Array=entry.keys()
		keys.sort()
		expect(keys==ENTRY_KEYS,label+": entry keys %s"%str(keys))
		expect(typeof(entry.get("slot"))==TYPE_INT and typeof(entry.get("item"))==TYPE_STRING and typeof(entry.get("count"))==TYPE_INT and typeof(entry.get("themed"))==TYPE_BOOL and typeof(entry.get("offset"))==TYPE_VECTOR2,label+": entry %d field types"%i)
		expect(int(entry.get("slot",-1))==i,label+": entry %d has slot %d"%[i,i])
		if i<MD.SLOTS.size():expect(entry.get("offset")==MD.SLOTS[i],label+": entry %d offset is SLOTS[%d]"%[i,i])
		var item:=str(entry.get("item",""))
		expect(i==0 or item>last,label+": items strictly sorted (%s after %s)"%[item,last])
		last=item
		expect(int(entry.get("count",0))>0,label+": entry %d count > 0"%i)
	expect(entries.size()<=Market.MAX_KINDS,label+": at most MAX_KINDS entries")

# 2b. shelf() shapes, sorting, cap, themed, no mutation, determinism.
func test_shelf_shapes()->void:
	expect(Market.category_of("radish")=="produce" and Market.category_of("carrot")=="produce" and Market.category_of("egg")=="produce","radish/carrot/egg are produce")
	expect(Market.category_of("soup")=="dish" and Market.category_of("salad")=="dish","soup/salad are dishes")
	expect(Market.category_of("bluebell")=="flower" and Market.category_of("chime_herb")=="flower","bluebell/chime_herb are flowers")
	# Fallback (no prices): theme dish.
	var v:=make_view({"stock":{"soup":3,"radish":1,"bluebell":2}})
	var entries:Array=MD.shelf(v)
	check_shelf(entries,"Three kinds")
	expect(items_of(entries)==["bluebell","radish","soup"],"Sorted by item id: %s"%str(items_of(entries)))
	if entries.size()==3:
		expect(int(entries[0].count)==2 and int(entries[1].count)==1 and int(entries[2].count)==3,"Counts follow the stock")
		expect(entries[0].themed==false and entries[1].themed==false and entries[2].themed==true,"Fallback: only soup is themed on a dish day")
	# Same stock on a produce day.
	var produce_day:Array=MD.shelf(make_view({"theme":"produce","stock":{"soup":3,"radish":1,"bluebell":2}}))
	expect(produce_day.size()==3 and produce_day[1].themed==true and produce_day[0].themed==false and produce_day[2].themed==false,"Fallback: only radish is themed on a produce day")
	var no_theme:Array=MD.shelf(make_view({"theme":"","stock":{"soup":3}}))
	expect(no_theme.size()==1 and no_theme[0].themed==false,"Empty theme -> nothing themed")
	# Cap at MAX_KINDS (sorted first four).
	var six:={"soup":1,"radish":1,"bluebell":1,"carp":1,"egg":1,"salad":1}
	var capped:Array=MD.shelf(make_view({"stock":six}))
	check_shelf(capped,"Six kinds")
	expect(items_of(capped)==["bluebell","carp","egg","radish"],"Six kinds -> first four sorted ids: %s"%str(items_of(capped)))
	# Explicit prices win over the category fallback.
	var prices:={"soup":{"themed":false},"radish":{"themed":true},"bluebell":{"category":"flower"}}
	var priced:Array=MD.shelf(make_view({"prices":prices,"stock":{"soup":3,"radish":1,"bluebell":2,"salad":1}}))
	expect(items_of(priced)==["bluebell","radish","salad","soup"],"Priced shelf order")
	if priced.size()==4:
		expect(priced[0].themed==false,"prices[bluebell] without themed -> false")
		expect(priced[1].themed==true,"prices[radish].themed true wins over category")
		expect(priced[2].themed==true,"Item missing from prices falls back to category (salad on a dish day)")
		expect(priced[3].themed==false,"prices[soup].themed false wins over category")
	var bad_prices:Array=MD.shelf(make_view({"prices":[],"stock":{"soup":1}}))
	expect(bad_prices.size()==1 and bad_prices[0].themed==true,"Non-dictionary prices -> category fallback")
	var empty_prices:Array=MD.shelf(make_view({"prices":{},"stock":{"radish":1}}))
	expect(empty_prices.size()==1 and empty_prices[0].themed==false,"Empty prices -> category fallback")
	# No mutation, determinism.
	var input:=make_view({"prices":prices,"stock":{"soup":3.0,"radish":1,"bluebell":2,"salad":1,"egg":1,"zz":0}})
	var before:PackedByteArray=var_to_bytes(input)
	var a:Array=MD.shelf(input)
	var _t:Array=MD.themed_items(input)
	var _r:String=MD.remark(input,{"soup":"x"})
	var _l:String=MD.remark_line(make_view({"open":true,"stalls_today":1,"stock":input.stock}))
	expect(var_to_bytes(input)==before,"shelf/themed_items/remark do not mutate their input")
	var b:Array=MD.shelf(input)
	expect(var_to_str(a)==var_to_str(b),"shelf is deterministic")
	if a.size()>0:
		(a[0] as Dictionary).item="mutated"
		(a[0] as Dictionary).count=99
	expect(var_to_str(MD.shelf(input))==var_to_str(b),"Mutating a returned entry does not leak into later shelves")

# 3. themed_items().
func test_themed_items()->void:
	expect(MD.themed_items({}).is_empty(),"Empty view -> no themed items")
	expect(MD.themed_items(make_view({"unlocked":false,"stock":{"soup":1}})).is_empty(),"Locked -> no themed items")
	var v:=make_view({"stock":{"soup":1,"salad":2,"radish":3,"bluebell":1}})
	expect(MD.themed_items(v)==["salad","soup"],"Dish day: sorted themed subset %s"%str(MD.themed_items(v)))
	var flower:=make_view({"theme":"flower","stock":{"soup":1,"chime_herb":2,"bluebell":1}})
	expect(MD.themed_items(flower)==["bluebell","chime_herb"],"Flower day: sorted themed subset")
	expect(MD.themed_items(make_view({"theme":"produce","stock":{"soup":1}})).is_empty(),"No themed item -> empty")
	var priced:=make_view({"prices":{"radish":{"themed":true},"soup":{"themed":false}},"stock":{"soup":1,"radish":2}})
	expect(MD.themed_items(priced)==["radish"],"themed_items follows prices[item].themed")
	# Only the capped shelf counts.
	var six:=make_view({"stock":{"soup":1,"radish":1,"bluebell":1,"carp":1,"egg":1,"salad":1}})
	expect(MD.themed_items(six).is_empty(),"Dishes beyond the four shown slots are not themed items")

# 4. remark() / remark_line().
func test_remark()->void:
	var names:={"soup":"蘿蔔湯","salad":"菜園沙拉","radish":"白蘿蔔","carrot":"糖心胡蘿蔔"}
	var stocked:={"soup":1,"salad":2,"radish":3}
	# Locked / no customers.
	expect(MD.remark({})=="","Empty view -> no remark")
	expect(MD.remark(make_view({"unlocked":false,"open":true,"stalls_today":3,"stock":stocked}))=="","Locked -> no remark")
	expect(MD.remark({"open":true,"stalls_today":3,"stock":stocked})=="","Missing unlocked -> no remark")
	for garbage in [0,-1,-3.0,0.5,"2","",null,[],{},Vector2(1,1)]:
		expect(MD.remark(make_view({"open":true,"stalls_today":garbage,"stock":stocked}))=="","stalls_today %s -> no remark"%var_to_str(garbage))
	var no_stalls:Dictionary=make_view({"open":true,"stock":stocked})
	no_stalls.erase("stalls_today")
	expect(MD.remark(no_stalls)=="","Missing stalls_today -> no remark")
	# Closed.
	expect(MD.remark(make_view({"stalls_today":2,"stock":stocked}))==MD.REMARK_CLOSED,"Customers but not open -> REMARK_CLOSED")
	expect(MD.remark(make_view({"stalls_today":1.0,"stock":{}}))==MD.REMARK_CLOSED,"Float stalls, not open, empty -> REMARK_CLOSED")
	var no_open:Dictionary=make_view({"stalls_today":2,"stock":stocked})
	no_open.erase("open")
	expect(MD.remark(no_open)==MD.REMARK_CLOSED,"Missing open -> REMARK_CLOSED")
	# Empty.
	expect(MD.remark(make_view({"open":true,"stalls_today":1,"stock":{}}))==MD.REMARK_EMPTY,"Open, no stock -> REMARK_EMPTY")
	expect(MD.remark(make_view({"open":true,"stalls_today":2,"stock":{"radish":0,"soup":-1}}))==MD.REMARK_EMPTY,"Open, only zero/negative counts -> REMARK_EMPTY")
	expect(MD.remark(make_view({"open":true,"stalls_today":2,"stock":"soup:3"}))==MD.REMARK_EMPTY,"Open, garbage stock -> REMARK_EMPTY")
	# Themed: sorted themed items [salad, soup], pick rotates by day.
	expect(MD.REMARK_THEMED%["料理","蘿蔔湯"]=="「今天想找料理，這攤剛好有蘿蔔湯，先看這個。」","Themed format literal")
	var themed_cases:=[[0,"salad"],[1,"soup"],[2,"salad"],[3,"soup"],[-1,"soup"],[-2,"salad"],[5.0,"soup"],[4.9,"salad"]]
	for pair:Array in themed_cases:
		var day_value:Variant=pair[0]
		var pick:String=pair[1]
		var v:=make_view({"open":true,"stalls_today":2,"day":day_value,"stock":stocked})
		var expected:String=MD.REMARK_THEMED%[str(Market.CATEGORY_NAMES["dish"]),str(names[pick])]
		expect(MD.remark(v,names)==expected,"Themed day %s picks %s: %s"%[str(day_value),pick,MD.remark(v,names)])
		expect(MD.remark(v)==MD.REMARK_THEMED%["料理",pick],"Themed day %s without names falls back to the id"%str(day_value))
		expect(MD.remark_line(v,names)==MD.REMARK_PREFIX+expected+MD.REMARK_NOTE,"remark_line wraps the themed remark")
	for garbage_day in ["3",null,[],Vector2(1,1)]:
		var gv:=make_view({"open":true,"stalls_today":2,"day":garbage_day,"stock":stocked})
		expect(MD.remark(gv,names)==MD.REMARK_THEMED%["料理","菜園沙拉"],"Non-numeric day %s behaves like day 0"%var_to_str(garbage_day))
	var missing_day:Dictionary=make_view({"open":true,"stalls_today":2,"stock":stocked})
	missing_day.erase("day")
	expect(MD.remark(missing_day,names)==MD.REMARK_THEMED%["料理","菜園沙拉"],"Missing day behaves like day 0")
	expect(MD.remark(make_view({"open":true,"stalls_today":1,"day":7,"stock":{"soup":2}}),{"salad":"x"})=="「今天想找料理，這攤剛好有soup，先看這個。」","Names without the item fall back to the item id")
	# Themed wins over variety when >=3 kinds include a themed one.
	var four:=make_view({"open":true,"stalls_today":1,"day":0,"stock":{"radish":1,"carrot":1,"egg":1,"soup":1}})
	expect(MD.remark(four,names)==MD.REMARK_THEMED%["料理","蘿蔔湯"],"Themed beats variety")
	# Prices decide themed; unknown theme name falls back to the theme id.
	var priced:=make_view({"open":true,"stalls_today":1,"day":0,"theme":"toys","prices":{"radish":{"themed":true}},"stock":{"radish":1}})
	expect(MD.remark(priced,names)==MD.REMARK_THEMED%["toys","白蘿蔔"],"Unknown theme name falls back to the theme id")
	# Variety: no themed items and >=3 kinds.
	expect(MD.remark(make_view({"open":true,"stalls_today":1,"stock":{"radish":1,"carrot":1,"egg":1}}),names)==MD.REMARK_VARIETY,"Three non-themed kinds -> REMARK_VARIETY")
	expect(MD.remark(make_view({"open":true,"stalls_today":1,"stock":{"radish":1,"carrot":1,"egg":1,"bluebell":4}}))==MD.REMARK_VARIETY,"Four non-themed kinds -> REMARK_VARIETY")
	expect(MD.remark_line(make_view({"open":true,"stalls_today":1,"stock":{"radish":1,"carrot":1,"egg":1}}))==MD.REMARK_PREFIX+MD.REMARK_VARIETY+MD.REMARK_NOTE,"remark_line wraps REMARK_VARIETY")
	# Other: 1-2 non-themed kinds, pick rotates by day over the sorted shelf [carrot, radish].
	expect(MD.REMARK_OTHER%["白蘿蔔","料理"]=="「白蘿蔔看起來不錯，不過今天大家先找料理。」","Other format literal")
	expect(MD.remark(make_view({"open":true,"stalls_today":1,"day":9,"stock":{"radish":2}}),names)=="「白蘿蔔看起來不錯，不過今天大家先找料理。」","One non-themed kind -> REMARK_OTHER")
	expect(MD.remark(make_view({"open":true,"stalls_today":1,"day":9,"stock":{"radish":2}}))=="「radish看起來不錯，不過今天大家先找料理。」","REMARK_OTHER without names uses the id")
	var other_cases:=[[0,"carrot"],[1,"radish"],[2,"carrot"],[-1,"radish"]]
	for pair:Array in other_cases:
		var day_value:Variant=pair[0]
		var pick:String=pair[1]
		var v:=make_view({"open":true,"stalls_today":1,"day":day_value,"stock":{"radish":2,"carrot":1}})
		var expected:String=MD.REMARK_OTHER%[str(names[pick]),"料理"]
		expect(MD.remark(v,names)==expected,"Other day %s picks %s: %s"%[str(day_value),pick,MD.remark(v,names)])
	expect(MD.remark(make_view({"open":true,"stalls_today":1,"day":0,"theme":"flower","stock":{"radish":2,"carrot":1}}),names)==MD.REMARK_OTHER%["糖心胡蘿蔔","花"],"Other uses the theme's category name")
	# remark_line is empty exactly when remark is empty.
	for quiet:Dictionary in [{},make_view({}),make_view({"stalls_today":0,"open":true,"stock":stocked}),make_view({"unlocked":false,"stalls_today":3})]:
		expect(MD.remark(quiet)=="" and MD.remark_line(quiet)=="","No remark -> empty remark_line")
	expect(MD.remark_line(make_view({"stalls_today":2}))==MD.REMARK_PREFIX+MD.REMARK_CLOSED+MD.REMARK_NOTE,"remark_line wraps REMARK_CLOSED")
	expect(MD.remark_line(make_view({"open":true,"stalls_today":2}))==MD.REMARK_PREFIX+MD.REMARK_EMPTY+MD.REMARK_NOTE,"remark_line wraps REMARK_EMPTY")
	# Same day, same stock, other unrelated fields changed -> same remark.
	var base:=make_view({"open":true,"stalls_today":1,"day":5,"stock":stocked})
	var noisy:=make_view({"open":true,"stalls_today":4,"day":5,"stock":stocked,"till":99,"total":500,"visitors_estimate":2,"report":{"sold":{"soup":1}}})
	expect(MD.remark(base,names)==MD.remark(noisy,names),"Remark only depends on day/theme/stock within a day")

## Expected remark for an open stall, built independently from the view.
static func expected_open_remark(v:Dictionary,names:Dictionary)->String:
	var stock:Dictionary=v.stock
	var items:Array=stock.keys()
	items.sort()
	if items.is_empty():return MD.REMARK_EMPTY
	var prices:Dictionary=v.prices
	var themed:=[]
	for item in items:
		var row:Dictionary=prices.get(item,{})
		if row.get("themed",false)==true:themed.append(item)
	var day_index:=int(v.day)
	var theme:=str(v.theme)
	var theme_name:=str(Market.CATEGORY_NAMES.get(theme,theme))
	if not themed.is_empty():
		var pick:String=themed[posmod(day_index,themed.size())]
		return MD.REMARK_THEMED%[theme_name,str(names.get(pick,pick))]
	if items.size()>=MD.VARIETY_KINDS:return MD.REMARK_VARIETY
	var other:String=items[posmod(day_index,items.size())]
	return MD.REMARK_OTHER%[str(names.get(other,other)),theme_name]

## shelf(view) must list exactly the view's stock, sorted, with themed from prices.
func shelf_matches(v:Dictionary,label:String)->void:
	var entries:Array=MD.shelf(v)
	check_shelf(entries,label)
	var stock:Dictionary=v.stock
	var items:Array=stock.keys()
	items.sort()
	expect(items_of(entries)==items,label+": shelf items %s == stock %s"%[str(items_of(entries)),str(items)])
	var prices:Dictionary=v.prices
	for entry:Dictionary in entries:
		var item:String=entry.item
		var row:Dictionary=prices.get(item,{})
		expect(int(entry.count)==int(stock.get(item,0)),label+": %s count %d == stock %d"%[item,int(entry.count),int(stock.get(item,0))])
		expect(entry.themed==(row.get("themed",false)==true),label+": %s themed follows prices"%item)

## shelf/remark over world views must not change world state.
func read_only(w,tokens:Array,label:String)->void:
	var before:PackedByteArray=var_to_bytes(w.state)
	for token:String in tokens:
		var v:=view(w,token)
		var _shelf:Array=MD.shelf(v)
		var _themed:Array=MD.themed_items(v)
		var _remark:String=MD.remark(v,{"soup":"x"})
		var _line:String=MD.remark_line(v)
	expect(var_to_bytes(w.state)==before,label+": shelf/remark leave world state byte-identical")

# 5. Real World integration.
func test_world_integration()->void:
	var a:="display_ann"
	var b:="display_bob"
	var names:={"soup":"蘿蔔湯","salad":"菜園沙拉","radish":"白蘿蔔","carrot":"糖心胡蘿蔔","bluebell":"風鈴草"}
	var w:=make_world([a,b],1,false)
	expect(MD.shelf(view(w,a)).is_empty() and MD.remark(view(w,a))=="" and MD.remark_line(view(w,a))=="","Before the picnic: empty shelf, no remark")
	read_only(w,[a,b],"Locked world")
	w.state.picnic=true # PRESET
	var cell:=stall(w)
	expect(cell!=Market.NO_CELL,"Stall cell exists after the picnic")
	stand(w,a,cell)
	stand(w,b,cell)
	var va0:=view(w,a)
	expect(va0.unlocked==true and int(va0.day)==1 and str(va0.theme)=="dish","World day 1, theme dish, unlocked")
	expect(MD.shelf(va0).is_empty() and MD.remark(va0)=="","Unlocked, nothing stocked: empty shelf, no remark")
	# Ann stocks via World.act.
	expect(bool(act(w,a,"market_stock",cell,"soup:4").get("ok",false)),"Ann stocks soup via World.act")
	expect(bool(act(w,a,"market_stock",cell,"salad:3").get("ok",false)),"Ann stocks salad via World.act")
	expect(bool(act(w,a,"market_stock",cell,"radish:2").get("ok",false)),"Ann stocks radish via World.act")
	var va:=view(w,a)
	var vb:=view(w,b)
	expect(va.stock=={"soup":4,"salad":3,"radish":2},"Ann's view stock %s"%str(va.stock))
	shelf_matches(va,"Ann stocked")
	var sa:Array=MD.shelf(va)
	expect(items_of(sa)==["radish","salad","soup"] and sa.size()==3 and int(sa[0].count)==2 and int(sa[1].count)==3 and int(sa[2].count)==4,"Ann's shelf: radish 2, salad 3, soup 4")
	if sa.size()==3:expect(sa[0].themed==false and sa[1].themed==true and sa[2].themed==true,"Dish day: salad and soup tags are themed")
	expect(MD.shelf(vb).is_empty() and MD.themed_items(vb).is_empty(),"Bob's view yields an empty shelf (never sees Ann's goods)")
	expect(MD.remark(va,names)=="" and MD.remark(vb,names)=="","Before anyone opens: no remark for either player")
	read_only(w,[a,b],"Stocked, nobody open")
	# Ann opens.
	expect(bool(act(w,a,"market_open",cell,"").get("ok",false)),"Ann opens via World.act")
	va=view(w,a)
	vb=view(w,b)
	expect(va.open==true and int(va.stalls_today)==1 and vb.open==false and int(vb.stalls_today)==1,"One open stall seen by both views")
	var ann_remark:=MD.remark(va,names)
	expect(ann_remark==expected_open_remark(va,names),"Ann's remark matches her stock: "+ann_remark)
	expect(ann_remark=="「今天想找料理，這攤剛好有蘿蔔湯，先看這個。」","Day 1 themed pick over [salad, soup] is soup: "+ann_remark)
	expect(MD.remark_line(va,names)==MD.REMARK_PREFIX+ann_remark+MD.REMARK_NOTE,"Ann's remark_line")
	expect(MD.remark(vb,names)==MD.REMARK_CLOSED and MD.remark_line(vb)==MD.REMARK_PREFIX+MD.REMARK_CLOSED+MD.REMARK_NOTE,"Bob (not open) gets REMARK_CLOSED")
	expect(MD.shelf(vb).is_empty(),"Bob still sees an empty shelf after Ann opens")
	read_only(w,[a,b],"Ann open")
	# Bob stocks two non-themed kinds and opens.
	expect(bool(act(w,b,"market_stock",cell,"bluebell:6").get("ok",false)),"Bob stocks bluebell via World.act")
	expect(bool(act(w,b,"market_stock",cell,"carrot:6").get("ok",false)),"Bob stocks carrot via World.act")
	expect(bool(act(w,b,"market_open",cell,"").get("ok",false)),"Bob opens via World.act")
	vb=view(w,b)
	shelf_matches(vb,"Bob stocked")
	expect(items_of(MD.shelf(vb))==["bluebell","carrot"],"Bob's shelf only has Bob's goods")
	expect(not items_of(MD.shelf(view(w,a))).has("carrot") and not items_of(MD.shelf(view(w,a))).has("bluebell"),"Ann's shelf never shows Bob's goods")
	var bob_remark:=MD.remark(vb,names)
	expect(bob_remark==expected_open_remark(vb,names) and bob_remark==MD.REMARK_OTHER%["糖心胡蘿蔔","料理"],"Bob's remark: day 1 other pick over [bluebell, carrot] is carrot: "+bob_remark)
	read_only(w,[a,b],"Two stalls open")
	# Ann takes everything back (Bob's stall keeps customers on the plaza).
	expect(bool(act(w,a,"market_take",cell,"soup:4").get("ok",false)),"Ann takes soup back via World.act")
	expect(bool(act(w,a,"market_take",cell,"salad:3").get("ok",false)),"Ann takes salad back via World.act")
	expect(bool(act(w,a,"market_take",cell,"radish:2").get("ok",false)),"Ann takes radish back via World.act")
	va=view(w,a)
	expect(va.stock.is_empty() and va.open==true and int(va.stalls_today)==1,"Ann open with empty stock, Bob's stall still counted (%s)"%str(va.stalls_today))
	expect(MD.shelf(va).is_empty(),"Ann's shelf is empty after taking everything back")
	expect(MD.remark(va,names)==MD.REMARK_EMPTY,"Ann's remark is REMARK_EMPTY")
	expect(MD.remark(view(w,b),names)==bob_remark,"Bob's remark unchanged by Ann taking her goods back")
	read_only(w,[a,b],"Ann emptied")
	# PRESET: jump to one second before midnight, then really step across it.
	w.state.time=DAY*2.0-1.0
	expect(MD.remark(view(w,b),names)==bob_remark,"Just before midnight Bob's remark is unchanged")
	var steps:=0
	while Market.day(now_of(w))<2 and steps<10:
		expect(w.step(0.5,true),"World.step tick %d succeeds"%steps)
		steps+=1
	expect(Market.day(now_of(w))==2,"World.step crossed midnight (%d ticks)"%steps)
	va=view(w,a)
	vb=view(w,b)
	expect(int(va.stalls_today)==0 and int(vb.stalls_today)==0 and str(vb.theme)=="flower","After midnight: no stalls today, theme flower")
	expect(MD.remark(va,names)=="" and MD.remark(vb,names)=="" and MD.remark_line(va)=="" and MD.remark_line(vb)=="","After midnight: no remark for either player")
	expect(MD.shelf(va).is_empty(),"Ann's shelf stays empty after settlement")
	var report:Dictionary=vb.report
	var sold:Dictionary=report.get("sold",{})
	var remaining:={}
	for item in ["bluebell","carrot"]:
		var left:=6-int(sold.get(item,0))
		if left>0:remaining[item]=left
	expect(int(report.get("visitors",0))==Market.visitors_for(1),"Bob's report: one stall's visitors (%s)"%str(report))
	expect(vb.stock==remaining,"Bob's stock after settlement %s == stocked minus sold %s"%[str(vb.stock),str(remaining)])
	expect(not remaining.is_empty(),"Some goods remained unsold (12 stocked, %d visitors)"%Market.visitors_for(1))
	shelf_matches(vb,"Bob after settlement")
	for entry:Dictionary in MD.shelf(vb):
		expect(entry.themed==(str(entry.item)=="bluebell"),"Flower day: only bluebell is themed (%s)"%str(entry.item))
	read_only(w,[a,b],"Settled world")
