extends SceneTree
## C12 D14 彩虹蔬菜串 / 夏季市集 regression suite for res://scripts/summer_market.gd and its World,
## SaveSchema and Session integration (headless, no UI).
##
## PRESET (written straight into world state, not earned): state.picnic, state.time, player position,
## inventory and coins. Everything else goes through World.act (the real request / receipt / save path).
## Covers: calendar (every year's summer, never out of it by accident), picnic / region / cell / reach
## gates, all three root options, rejected actions leaving the world byte-identical, retry replay
## (same request id) and a fresh request after success, permanent retention across seasons / years and
## save reload, schema tampering, the year-round market staying untouched, own-only view and the
## contract helpers the cooking gate reads.
const World=preload("res://scripts/world.gd")
const Summer=preload("res://scripts/summer_market.gd")
const Market=preload("res://scripts/market_stall.gd")
const KitchenStove=preload("res://scripts/kitchen_stove.gd")
const DAY:=1440.0
const TOKEN:="summer-market-alpha-token"
const OTHER:="summer-market-beta-token"
var checks:=0
var failures:=0
var serial:=0

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func _initialize()->void:
	run.call_deferred()

func run()->void:
	test_calendar()
	test_flow_each_option()
	test_rejections()
	test_retry_and_repeat()
	test_retention_and_save()
	test_market_untouched()
	test_view_and_contract()
	test_first_batch()
	print("SUMMER_MARKET_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

func make_world(day:int=16,picnic:bool=true,tokens:Array=[TOKEN])->World:
	var w:=World.new()
	for token:String in tokens:
		w.add_player(token,token.left(6))
		stand(w,token)
		var inv:Dictionary=w.state.players[token].inventory
		inv.eggplant=2
		inv.radish=2
		inv.carrot=2
		w.state.players[token].coins=200
	w.state.picnic=picnic
	w.state.time=DAY*day+120.0
	return w

func stall(w)->Vector2i:
	return Market.cell_for(w.state)

func stand(w,token:String)->void:
	var cell:=Market.CANDIDATES[0] as Vector2i
	var p:Dictionary=w.state.players[token]
	p.x=float(cell.x)+0.5
	p.y=float(cell.y)+1.5

func act(w,token:String,extra:String,request:String="",cell:Vector2i=Vector2i(-9,-9))->Dictionary:
	serial+=1
	var id:String=request if not request.is_empty() else "summer-req-%d"%serial
	var at:=stall(w) if cell==Vector2i(-9,-9) else cell
	return w.act(token,id,Summer.ACTION,at,extra)

func reject(w,token:String,extra:String,label:String,cell:Vector2i=Vector2i(-9,-9))->void:
	var before:PackedByteArray=var_to_bytes(w.state)
	var r:Dictionary=act(w,token,extra,"",cell)
	expect(not bool(r.get("ok",true)),label+": rejected")
	expect(not str(r.get("message","")).is_empty(),label+": explains itself")
	expect(var_to_bytes(w.state)==before,label+": world byte-identical")

func person(w,token:String=TOKEN)->Dictionary:
	return w.state.players[token]

# ---------------------------------------------------------------- calendar --
func test_calendar()->void:
	for year in 4:
		var base:=year*56
		for d in 56:
			var summer:=d>=14 and d<28
			expect(Summer.in_season(base+d)==summer,"day %d summer=%s"%[base+d,str(summer)])
			expect((Summer.days_left(base+d)>0)==summer,"days_left>0 only in summer (day %d)"%(base+d))
			expect((Summer.days_until(base+d)==0)==summer,"days_until==0 only in summer (day %d)"%(base+d))
			if not summer:expect(Summer.in_season(base+d+Summer.days_until(base+d)),"days_until lands on summer (day %d)"%(base+d))
	expect(Summer.days_left(14)==14 and Summer.days_left(27)==1,"days_left counts today: 14 on the first day, 1 on the last")
	expect(Summer.days_until(0)==14 and Summer.days_until(28)==42 and Summer.days_until(13)==1,"days_until from spring / autumn")

# ---------------------------------------------------------------- the event --
func test_flow_each_option()->void:
	for root:String in Summer.ROOT_OPTIONS:
		var w:=make_world()
		var coins_before:=int(person(w).coins)
		var r:=act(w,TOKEN,root)
		expect(bool(r.get("ok",false)),"root option %s succeeds (%s)"%[root,str(r.get("message",""))])
		var p:=person(w)
		expect(Summer.recipe_known(p) and World.summer_market_known(p),"%s: recipe retained"%root)
		expect(int(p.inventory.get("eggplant",0))==1,"%s: one eggplant consumed"%root)
		if root==Summer.BOOTH:
			expect(int(p.coins)==coins_before-Summer.BOOTH_PRICE,"booth: pays %d coins"%Summer.BOOTH_PRICE)
			expect(int(p.inventory.radish)==2 and int(p.inventory.carrot)==2,"booth: no root consumed from the bag")
		else:
			expect(int(p.coins)==coins_before,"%s: no coins spent"%root)
			expect(int(p.inventory.get(root,0))==1,"%s: one root consumed"%root)
		expect(not p.inventory.has("rainbow_skewer"),"%s: nothing handed back (no buy->sell loop)"%root)
		expect(p.summer_market.root==root and int(p.summer_market.day)==16,"%s: record names root and day"%root)
		expect(w.state.players[TOKEN].has("summer_market") and not p.has("market"),"%s: market record untouched"%root)

func test_rejections()->void:
	var w:=make_world(16,false)
	reject(w,TOKEN,"carrot","before the picnic (market locked)")
	w=make_world(3)
	reject(w,TOKEN,"carrot","spring")
	w=make_world(30)
	reject(w,TOKEN,"carrot","autumn")
	w=make_world()
	reject(w,TOKEN,"","empty option")
	reject(w,TOKEN,"turnip","unknown option")
	reject(w,TOKEN,"eggplant","eggplant is not a root option")
	reject(w,TOKEN,"carrot","wrong cell",stall(w)+Vector2i(3,0))
	person(w).x=float(stall(w).x)+8.5
	reject(w,TOKEN,"carrot","too far")
	stand(w,TOKEN)
	person(w).inventory.erase("eggplant")
	reject(w,TOKEN,"carrot","no eggplant")
	person(w).inventory.eggplant=1
	person(w).inventory.erase("carrot")
	reject(w,TOKEN,"carrot","no carrot")
	person(w).inventory.erase("radish")
	reject(w,TOKEN,"radish","no radish")
	person(w).coins=Summer.BOOTH_PRICE-1
	reject(w,TOKEN,"booth","booth short of coins")
	person(w).coins=Summer.BOOTH_PRICE
	expect(bool(act(w,TOKEN,"booth").ok),"booth with exactly the price works")
	expect(int(person(w).coins)==0,"booth leaves 0 coins")
	var corrupt:=make_world()
	person(corrupt)[Summer.KEY]={"recipe":false}
	reject(corrupt,TOKEN,"carrot","corrupt record")

func test_retry_and_repeat()->void:
	var w:=make_world()
	var first:=act(w,TOKEN,"carrot","summer-retry-1")
	expect(bool(first.ok),"first request succeeds")
	var snapshot:PackedByteArray=var_to_bytes(w.state)
	var replay:=act(w,TOKEN,"carrot","summer-retry-1")
	expect(var_to_bytes(replay)==var_to_bytes(first),"same request id replays the stored receipt")
	expect(var_to_bytes(w.state)==snapshot,"replay changes nothing (no second eggplant / carrot taken)")
	expect(int(person(w).inventory.eggplant)==1 and int(person(w).inventory.carrot)==1,"ingredients spent exactly once")
	reject(w,TOKEN,"radish","a fresh request after learning is refused and spends nothing")
	var failed:=act(make_world(3),TOKEN,"carrot","summer-retry-2")
	expect(not bool(failed.ok),"out-of-season failure")
	# A failed request is not cached as a receipt: after it becomes summer the same id would just run again.
	var retry_world:=make_world(3)
	expect(not bool(act(retry_world,TOKEN,"carrot","summer-retry-3").ok),"fails in spring")
	expect(not person(retry_world).receipts.has("summer-retry-3"),"failure stores no receipt")
	retry_world.state.time=DAY*16+120.0
	expect(bool(act(retry_world,TOKEN,"carrot","summer-retry-3").ok),"the retry works once summer arrives")

func test_retention_and_save()->void:
	var w:=make_world()
	expect(bool(act(w,TOKEN,"radish").ok),"learn in summer")
	var path:=OS.get_environment("TEMP").path_join("summer-market-%s.json"%Crypto.new().generate_random_bytes(6).hex_encode())
	w.save_path=path
	expect(w.save() and w.load_world(path),"record survives save + reload")
	expect(Summer.recipe_known(person(w)),"still known after reload")
	for day in [30,45,56+3,56*3+20]:
		w.state.time=DAY*day+5.0
		expect(Summer.recipe_known(person(w)),"still known on day %d (out of season too)"%day)
		expect(bool(w.summer_market_view(TOKEN).recipe),"view says learned on day %d"%day)
		expect(not bool(act(w,TOKEN,"carrot").ok),"cannot be learned twice on day %d"%day)
	for file:String in [path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	var now:=DAY*20
	expect(Summer.valid({"recipe":true,"root":"carrot","day":16.0},now),"valid: float day from JSON")
	expect(not Summer.valid({"recipe":true,"root":"carrot","day":21},now),"invalid: learned in the future")
	expect(not Summer.valid({"recipe":false,"root":"carrot","day":16},now),"invalid: recipe false")
	expect(not Summer.valid({"recipe":true,"root":"turnip","day":16},now),"invalid: unknown root")
	expect(not Summer.valid({"recipe":true,"root":"carrot"},now),"invalid: missing field")
	expect(not Summer.valid({"recipe":true,"root":"carrot","day":16,"extra":1},now),"invalid: extra field")
	expect(not Summer.valid({"recipe":true,"root":"carrot","day":1.5},now),"invalid: fractional day")
	expect(not Summer.valid("yes",now),"invalid: not a dictionary")

func test_market_untouched()->void:
	var w:=make_world()
	var market_before:Variant=var_to_bytes(w.market_view(TOKEN))
	var cell_before:=stall(w)
	expect(bool(act(w,TOKEN,"carrot").ok),"learn")
	expect(var_to_bytes(w.market_view(TOKEN))==market_before,"market view (theme, prices, stock) is untouched")
	expect(stall(w)==cell_before,"stall cell unchanged")
	# The year-round market still works in every season, learned or not.
	for day in [3,16,30,45]:
		var v:=make_world(day)
		v.state.players[TOKEN].inventory.radish=5
		var s:=v.act(TOKEN,"mk-%d"%day,"market_stock",stall(v),"radish:2")
		expect(bool(s.ok),"market_stock still works on day %d (%s)"%[day,str(s.get("message",""))])
		expect(bool(v.act(TOKEN,"mo-%d"%day,"market_open",stall(v),"").ok),"market_open still works on day %d"%day)

func test_view_and_contract()->void:
	var w:=make_world(3)
	var v:Dictionary=w.summer_market_view(TOKEN)
	expect(not bool(v.in_season) and not bool(v.can_taste) and int(v.days_until)==11,"spring: not in season, 11 days to go")
	expect(str(v.reason).contains("11"),"spring reason says how long")
	expect(not str(v.guidance).is_empty(),"guidance always present")
	w=make_world(16)
	v=w.summer_market_view(TOKEN)
	expect(bool(v.in_season) and bool(v.can_taste) and int(v.days_left)==12,"summer day 16: 12 days left, playable")
	expect(v.roots.size()==3,"three root options")
	var ids:=[]
	for row:Dictionary in v.roots:ids.append(row.id)
	expect(ids==["radish","carrot","booth"],"option order radish / carrot / booth")
	person(w).inventory.erase("eggplant")
	expect(not bool(w.summer_market_view(TOKEN).can_taste) and str(w.summer_market_view(TOKEN).reason).contains("茄子"),"no eggplant: guided to the summer crop")
	var locked:=make_world(16,false)
	expect(not bool(locked.summer_market_view(TOKEN).unlocked),"before the picnic the event is not open")
	# Contract helpers the cooking gate reads.
	var entry:=Summer.gate_entry()
	expect(entry.kind=="market" and not str(entry.message).is_empty() and not str(entry.button).is_empty() and not str(entry.tip).is_empty(),"gate_entry shape")
	expect(not Summer.recipe_known({}) and not Summer.recipe_known({"summer_market":{"recipe":false}}),"recipe_known false for fresh / false")
	expect(not Summer.recipe_known_in({}) and Summer.recipe_known_in({"own_summer_market":{"recipe":true}}),"recipe_known_in reads own_summer_market.recipe")
	expect(KitchenStove.dish("rainbow_skewer").source=="夏季市集","D14 source in the stove table is 夏季市集")
	# Privacy: the other player's record never reaches a snapshot taken for someone else.
	var two:=make_world(16,true,[TOKEN,OTHER])
	expect(bool(act(two,TOKEN,"carrot").ok),"first player learns")
	expect(not bool(two.summer_market_view(OTHER).recipe),"second player has not learned it (per player)")

func test_first_batch()->void:
	var w:=make_world(16,true,[TOKEN,OTHER])
	var stove:=Vector2i(41,33)
	for y in range(32,36):
		for x in range(40,45):w.state.removed[World.key(Vector2i(x,y))]=true
	person(w).x=41.5
	person(w).y=35.5
	person(w).inventory={"wood":30,"stone":25,"clay":7,"eggplant":2}
	expect(w.act(TOKEN,"d14-batch-stove","build",stove,"kitchen_stove").ok,"Builds the C12 stove")
	var refused:=w.act(TOKEN,"d14-batch-locked","queue_cook",stove,Summer.DISH)
	expect(not refused.ok and refused.message==Summer.GATE_MESSAGE,"New work is gated before the summer tasting")
	stand(w,TOKEN)
	expect(act(w,TOKEN,Summer.BOOTH).ok,"Can learn without bringing either out-of-season root")
	var coins_after_bundle:=int(person(w).coins)-Summer.ROOTS_PRICE
	var purchased:=w.act(TOKEN,"d14-batch-roots",Summer.BUY_ROOTS,stall(w))
	expect(purchased.ok and person(w).coins==coins_after_bundle and int(person(w).inventory.radish)==1 and int(person(w).inventory.carrot)==1,"Booth roots make a first batch possible in the same summer")
	expect(w.act(TOKEN,"d14-batch-roots",Summer.BUY_ROOTS,stall(w))==purchased,"A replay is free")
	expect(not w.act(TOKEN,"d14-batch-no-second",Summer.BUY_ROOTS,stall(w)).ok and person(w).coins==coins_after_bundle,"Only one bundle a day")
	expect(not w.act(OTHER,"d14-batch-friend",Summer.BUY_ROOTS,stall(w)).ok,"Another islander must learn first")
	person(w).x=41.5
	person(w).y=35.5
	expect(w.act(TOKEN,"d14-batch-cook","queue_cook",stove,Summer.DISH).ok,"Can queue the exact recipe after tendering both roots and the remaining eggplant")
	expect(w.step(61.0,true) and w.act(TOKEN,"d14-batch-claim","claim_cook",stove).ok and int(person(w).inventory.get(Summer.DISH,0))==3,"First batch produces its three servings")
	w.state.time=DAY*30+120.0
	expect(not w.stove_dish_locked(person(w),KitchenStove.KIND,Summer.DISH),"Recipe stays unlocked in autumn")
