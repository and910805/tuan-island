extends SceneTree
## T093 經濟、配方與解鎖依賴檢查（第一批）。純資料：不建立 World、不讀寫存檔。
## 模型與限制見 scripts/economy_audit.gd 檔頭。

const Audit=preload("res://scripts/economy_audit.gd")
const World=preload("res://scripts/world.gd")
const Industry=preload("res://scripts/industry.gd")
const Mines=preload("res://scripts/mine_depths.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const Market=preload("res://scripts/market_stall.gd")

var checks:=0
var failures:=0

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func _initialize() -> void:
	test_engine_synthetic()
	var convs:Array=Audit.conversions()
	test_model_shape(convs)
	test_coverage(convs)
	test_xiaoli_scale_and_tool_uses(convs)
	test_c12_dishes(convs)
	test_reachability(convs)
	test_unlock_order(convs)
	test_certificate(convs)
	test_counterfactuals(convs)
	test_seed_returns()
	test_farming_and_prices()
	report(convs)
	print("ECONOMY AUDIT conversions=%d checks=%d failures=%d"%[convs.size(),checks,failures])
	quit(1 if failures else 0)

func ids_of(entries:Array) -> Array:
	var ids:=[]
	for entry:Dictionary in entries:ids.append(str(entry.id))
	ids.sort()
	return ids

## 檢查器本身：用手寫的小經濟確認抓得到、也不會亂抓。
func test_engine_synthetic() -> void:
	var c:=Audit.COIN
	# 買 5 賣 6：直接套利。
	var pump:=[Audit.conv("buy:x","buy",{c:5},{"x":1}),Audit.conv("sell:x","sell",{"x":1},{c:6})]
	var result:Dictionary=Audit.certificate(pump)
	expect(not result.stable,"buy 5 / sell 6 is not certified")
	expect(ids_of(result.violations)==["sell:x"],"buy 5 / sell 6 names the sale: %s"%str(result.violations))
	expect(not Audit.certificate_gaps(pump,result.value).is_empty(),"buy 5 / sell 6 leaves a gap")
	# 買 6 賣 5：沒有套利。
	var fair:=[Audit.conv("buy:x","buy",{c:6},{"x":1}),Audit.conv("sell:x","sell",{"x":1},{c:5})]
	result=Audit.certificate(fair)
	expect(result.stable and result.violations.is_empty(),"buy 6 / sell 5 is certified")
	expect(Audit.certificate_gaps(fair,result.value).is_empty(),"buy 6 / sell 5 has no gap")
	expect(is_equal_approx(float(result.value.x),5.0),"x is worth its sale price")
	# 買價與賣價相同：不賺不賠，可以通過。
	var even:=[Audit.conv("buy:x","buy",{c:5},{"x":1}),Audit.conv("sell:x","sell",{"x":1},{c:5})]
	result=Audit.certificate(even)
	expect(result.stable and Audit.certificate_gaps(even,result.value).is_empty(),"buy 5 / sell 5 is certified")
	# 買來的東西加工後比買價值錢。
	var craft_pump:=[Audit.conv("buy:x","buy",{c:5},{"x":1}),Audit.conv("craft:y","craft",{"x":2},{"y":1}),Audit.conv("sell:y","sell",{"y":1},{c:11})]
	result=Audit.certificate(craft_pump)
	expect(not result.stable and ids_of(result.violations)==["craft:y"],"buy 2x5, craft, sell 11 is caught at the craft: %s"%str(result.violations))
	craft_pump[2]=Audit.conv("sell:y","sell",{"y":1},{c:10})
	result=Audit.certificate(craft_pump)
	expect(result.stable and Audit.certificate_gaps(craft_pump,result.value).is_empty(),"buy 2x5, craft, sell 10 is certified")
	# 加工時多一樣買不到的材料：價值算在那樣材料上，不算套利。
	var mixed:=[Audit.conv("buy:x","buy",{c:5},{"x":1}),Audit.conv("craft:y","craft",{"x":1,"herb":1},{"y":1}),Audit.conv("sell:y","sell",{"y":1},{c:40}),Audit.conv("farm:herb","source",{},{"herb":1},[],true)]
	result=Audit.certificate(mixed)
	expect(result.stable and Audit.certificate_gaps(mixed,result.value).is_empty(),"a grown ingredient carries the extra value")
	expect(float(result.value.herb)>=35.0-0.001 and float(result.value.x)<=5.0+0.001,"herb >= 35 and x <= 5: %s"%str(result.value))
	# 沒有價目的東西越換越多（A 換 2B、B 換 A）。
	var loop:=[Audit.conv("a_to_b","craft",{"a":1},{"b":2}),Audit.conv("b_to_a","craft",{"b":1},{"a":1})]
	result=Audit.certificate(loop,200)
	expect(not result.stable and int(result.rounds)==200,"an item-doubling loop never settles")
	# 同一圈但每圈要賠（A 換 B、2B 換 A）。
	var lossy:=[Audit.conv("a_to_b","craft",{"a":1},{"b":1}),Audit.conv("b_to_a","craft",{"b":2},{"a":1})]
	result=Audit.certificate(lossy)
	expect(result.stable and Audit.certificate_gaps(lossy,result.value).is_empty(),"a lossy loop is certified")
	# 蓋了再拆、全額退回：中性。
	var neutral:=[Audit.conv("build:t","build",{"wood":3},{"@built:t":1}),Audit.conv("remove:t","remove",{"@built:t":1},{"wood":3}),Audit.conv("sell:wood","sell",{"wood":1},{c:2})]
	result=Audit.certificate(neutral)
	expect(result.stable and Audit.certificate_gaps(neutral,result.value).is_empty(),"build then remove at full refund is certified")
	# 拆除退得比蓋的多。
	neutral[1]=Audit.conv("remove:t","remove",{"@built:t":1},{"wood":4})
	result=Audit.certificate(neutral,200)
	expect(not result.stable,"a refund larger than the cost is caught")
	# 憑空變出東西（沒有投入、也不花時間）。
	var free:=[Audit.conv("gift","craft",{},{"x":1}),Audit.conv("sell:x","sell",{"x":1},{c:3})]
	result=Audit.certificate(free)
	expect(not result.stable and ids_of(result.violations)==["gift"],"an untimed conversion with no input is caught")
	# 要花時間的來源不受限制。
	var timed:=[Audit.conv("gather","source",{},{"x":1},[],true),Audit.conv("sell:x","sell",{"x":1},{c:3})]
	result=Audit.certificate(timed)
	expect(result.stable and Audit.certificate_gaps(timed,result.value).is_empty(),"a timed source is allowed to create value")
	# 解鎖：互相等待的兩項都拿不到；順著來的拿得到。
	var deadlock:=[Audit.conv("open_a","unlock",{"k":1},{"@mine:2":1},["@mine:3"]),Audit.conv("open_b","unlock",{"k":1},{"@mine:3":1},["@mine:2"]),Audit.conv("dig","source",{},{"k":1},[],true)]
	var reach:Dictionary=Audit.reachable(deadlock,[Audit.TIME])
	expect(reach.have.has("k") and not reach.have.has("@mine:2") and not reach.have.has("@mine:3"),"mutually waiting unlocks stay locked")
	deadlock[0]=Audit.conv("open_a","unlock",{"k":1},{"@mine:2":1})
	reach=Audit.reachable(deadlock,[Audit.TIME])
	expect(reach.have.has("@mine:2") and reach.have.has("@mine:3") and reach.fired.size()==3,"an ordered chain opens")
	# 材料只能在它自己解鎖的地方拿到。
	var circular:=[Audit.conv("open","unlock",{"gem":1},{"@mine:2":1}),Audit.conv("dig","source",{},{"gem":1},["@mine:2"],true)]
	reach=Audit.reachable(circular,[Audit.TIME])
	expect(not reach.have.has("gem") and reach.fired.is_empty(),"a material found only behind its own unlock is unreachable")
	reach=Audit.reachable(circular,[])
	expect(reach.have.is_empty() and int(reach.rounds)==1,"nothing is reachable from nothing")

func test_model_shape(convs:Array) -> void:
	var seen:={}
	for entry:Dictionary in convs:
		expect(not seen.has(entry.id),"conversion id is unique: %s"%entry.id)
		seen[entry.id]=true
		expect(not entry.out.is_empty(),"%s produces something"%entry.id)
		expect(bool(entry.timed)==entry["in"].has(Audit.TIME),"%s is timed exactly when it takes time"%entry.id)
		if not entry.timed:
			# 解鎖可以不收材料（第 3 層的工程沒有成本）；解鎖沒有價值、不能轉手。
			var only_gates:=true
			for item:String in entry.out:
				if not Audit.is_gate(item):only_gates=false
			expect(not entry["in"].is_empty() or (entry.kind=="unlock" and only_gates),"%s (untimed) takes something"%entry.id)
		for group:String in ["in","out"]:
			for item in entry[group]:
				expect(item is String and (Audit.is_pseudo(item) or World.NAMES.has(item)),"%s %s item exists: %s"%[entry.id,group,str(item)])
				var amount=entry[group][item]
				expect(amount is int and amount>0,"%s %s amount of %s is a positive integer"%[entry.id,group,str(item)])
		for item in entry.needs:
			expect(item is String and (Audit.is_pseudo(item) or World.NAMES.has(item)),"%s needs an existing item: %s"%[entry.id,str(item)])
		expect(not entry.out.has(Audit.TIME),"%s does not produce time"%entry.id)
		for item:String in entry["in"]:
			expect(not Audit.is_gate(item),"%s does not consume an unlock"%entry.id)
	for demand:Dictionary in Audit.demands():
		expect(not demand.items.is_empty(),"demand %s lists materials"%demand.id)
		for item in demand.items:
			expect(World.NAMES.has(item),"demand %s item exists: %s"%[demand.id,str(item)])
	# 手抄的規則對一下還讀得到的常數。
	expect(Tea.price_for("light","fiber")==36 and Tea.price_for("deep","fiber")==44 and Tea.price_for("light","jar")==48 and Tea.price_for("deep","jar")==56,"tea delivery prices")
	expect(Tea.RETURN_ITEM.size()==3 and not Tea.RETURN_ITEM.has("tea_spent_jar"),"three jar grades can be packed; a spent jar cannot")
	expect(Mines.COSTS.size()==Mines.MAX_DEPTH-1 and Mines.ORES.size()==Mines.MAX_DEPTH and Mines.YIELDS.size()==Mines.MAX_DEPTH,"mine tables cover 15 floors")
	expect(Audit.best_sale("radish")==Market.price_for(int(World.CROPS.radish.price),"produce",0),"best sale of a crop is its themed market price")
	expect(Audit.best_sale("wood")==2 and Audit.best_sale("sugar")==0 and Audit.best_sale("radish_seed")==0 and Audit.sale_table().get("milk")==36 and Audit.sale_table().get("wool")==48 and Audit.best_sale("milk")==47 and Audit.best_sale("wool")==63,"raw materials and livestock products have explicit prices; sugar and seeds do not sell")
	for item:String in Audit.sale_table():
		expect(Audit.best_sale(item)>=int(Audit.sale_table()[item]),"best sale of %s is at least the shipping price"%item)

## 每張表的每一列都進了模型，每個物品都有產出它的轉換。
func test_coverage(convs:Array) -> void:
	var ids:={}
	var produced:={}
	var consumed:={}
	var retained_tools:={}
	for tools:Array in Audit.TOOL_USES.values():
		for item:String in tools:retained_tools[item]=true
	for entry:Dictionary in convs:
		ids[entry.id]=true
		for item:String in entry.out:produced[item]=true
		for item:String in entry["in"]:consumed[item]=true
	for demand:Dictionary in Audit.demands():
		for item:String in demand.items:consumed[item]=true
	for id:String in World.CRAFT:expect(ids.has("craft:"+id),"CRAFT %s is modelled"%id)
	for id:String in World.RECIPES:expect(ids.has("cook:"+id),"RECIPES %s is modelled"%id)
	for id:String in Industry.PROCESS:expect(ids.has("process:"+id),"PROCESS %s is modelled"%id)
	for kind:String in World.BUILD:
		expect(ids.has("build:"+kind) and ids.has("remove:"+kind),"BUILD %s is modelled both ways"%kind)
	for kind:String in World.CROPS:
		expect(ids.has("farm:"+kind) and ids.has("buy:"+kind+"_seed") and (ids.has("seed_maker:"+kind+"_seed") == (kind not in World.SEED_MAKER.NURSERY_CROPS)),"crop %s has farm, seed purchase and its intended processing route"%kind)
		expect(World.NAMES.has(kind+"_seed"),"crop %s has a named seed"%kind)
	for fish:String in World.FISH:expect(ids.has("fish:"+fish),"fish %s is modelled"%fish)
	for item:String in Audit.sale_table():expect(ids.has("sell:"+item),"sale of %s is modelled"%item)
	for depth in range(1,Mines.MAX_DEPTH+1):expect(ids.has("mine:%d"%depth),"mine floor %d is modelled"%depth)
	for item:String in World.NAMES:
		if item=="mill_kit":
			expect(not produced.has(item) and World.LEGACY_MILL_COST.get(item)==1,"the original mill kit is tied to old saves and is never newly produced")
			continue
		expect(produced.has(item),"item has a source in the model: %s"%item)
	# 每個物品不是賣得掉、就是有地方用（裝飾套件用在建造）。
	for item:String in World.NAMES:
		# These tabletop pieces can move back to the backpack without being consumed.
		expect(consumed.has(item) or retained_tools.has(item) or item in ["tiller","seeder","harvester",World.INDUSTRY.TEA_SET,World.XIAOLI_SHOP.SCALE_ITEM] or item in World.INDUSTRY.SHELL_BOTTLES or (item=="mill_kit" and World.LEGACY_MILL_COST.get(item)==1),"item is used, collected or sold somewhere: %s"%item)

func test_xiaoli_scale_and_tool_uses(convs:Array) -> void:
	var shop=World.XIAOLI_SHOP
	var path:=convs.filter(func(entry:Dictionary):return entry.id in ["xiaoli:hang_sign",shop.SCALE_ACTION])
	expect(path.size()==2,"Scale model contains the sign and the separate reward claim")
	expect(not Audit.reachable(path,[Audit.TIME]).have.has(shop.SCALE_ITEM),"Time alone does not make the scale available")
	expect(Audit.reachable(path,[Audit.TIME,"plank"]).have.has(shop.SCALE_ITEM),"The plank path unlocks the scale")
	for entry:Dictionary in path:
		if entry.id==shop.SCALE_ACTION:
			expect(entry.needs==[Audit.XIAOLI_SIGN_HUNG] and entry.out=={shop.SCALE_ITEM:1} and entry.timed,"The finished sign gives access to one personal story reward")
		else:
			expect(entry["in"]=={"plank":2,Audit.TIME:1} and entry.out=={Audit.XIAOLI_SIGN_HUNG:1},"The sign uses the two planks from Xiaoli's final story stage")
	for action:String in Audit.TOOL_USES:
		for item:String in Audit.TOOL_USES[action]:
			var equipped:=World.active_mining_pick({item:1}) if action=="pick" else World.gathering_tool_upgrade(action,{item:1})
			expect(World.NAMES.has(item) and equipped==item,"Holding %s enables its %s action"%[item,action])

## C12: each D01-D16 dish is modelled with its canonical numbers on the 2x2 stove (its own `cook_c12:` conversion
## wherever they differ from the early stove's row), and every dish eaten through eat_meal has a real sink.
func test_c12_dishes(convs:Array) -> void:
	var by_id:={}
	for entry:Dictionary in convs:by_id[entry.id]=entry
	var sinks:={}
	for demand:Dictionary in Audit.demands():sinks[demand.id]=demand
	var big:=Audit.built(Industry.KITCHEN_STOVE)
	var distinct:=0
	for dish:Dictionary in World.KITCHEN_STOVE.DISHES:
		var id:String=dish.id
		var early:Dictionary=World.RECIPES[id]
		var same:bool=early.ingredients==dish.ingredients and int(early["yield"])==int(dish["yield"])
		if id in World.KITCHEN_STOVE.EXCLUSIVE:
			var only:Dictionary=by_id.get("cook:"+id,{})
			expect(not only.is_empty() and only["in"]==dish.ingredients and only.out=={id:int(dish["yield"])} and only.needs==[big],"%s exists only on the 2x2 stove with its canonical numbers"%id)
			expect(not by_id.has("cook_c12:"+id),"%s needs no second conversion"%id)
			continue
		var legacy:Dictionary=by_id.get("cook:"+id,{})
		expect(not legacy.is_empty() and legacy["in"]==early.ingredients and legacy.out=={id:int(early["yield"])} and legacy.needs==[Audit.built("stove")],"%s keeps the early stove's conversion"%id)
		if same:
			expect(not by_id.has("cook_c12:"+id),"%s has the same numbers on both stoves, so one conversion"%id)
			continue
		distinct+=1
		var canonical:Dictionary=by_id.get("cook_c12:"+id,{})
		expect(not canonical.is_empty() and canonical["in"]==dish.ingredients and canonical.out=={id:int(dish["yield"])} and canonical.needs==[big] and not canonical.timed,"%s is modelled with its canonical C12 numbers on the 2x2 stove"%id)
	expect(distinct>0,"at least one dish differs between the stoves")
	# Independent of the data tables: D04 bread is one flour (not the early two wheat).
	var bread:Dictionary=by_id.get("cook_c12:bread",{})
	expect(not bread.is_empty() and bread["in"]=={"flour":1} and bread.out=={"bread":1},"D04 bread is one flour on the 2x2 stove")
	for dish:Dictionary in World.KITCHEN_STOVE.DISHES:
		var id:String=dish.id
		if id in World.KITCHEN_STOVE.LEGACY_EAT:
			continue
		expect(sinks.has("eat_meal:"+id) and sinks["eat_meal:"+id].items=={id:1},"%s is consumed by eat_meal"%id)
	expect(sinks.has("eat_meal:forest_mushroom_soup") and sinks.has("eat_meal:rainbow_skewer"),"both C12-only dishes have an eating sink")
	expect(sinks.has("eat_rice_ball") and sinks.has("drink_ginger_tea"),"the two dishes with older eating actions keep their sinks")

func test_reachability(convs:Array) -> void:
	var reach:Dictionary=Audit.reachable(convs,Audit.start_items())
	var have:Dictionary=reach.have
	for item:String in World.NAMES:
		expect(have.has(item)==(item!="mill_kit"),"fresh character item sources respect acquisition rules: %s"%item)
	for entry:Dictionary in convs:
		expect(reach.fired.has(entry.id),"conversion can eventually be used: %s"%entry.id)
	for kind:String in World.BUILD:
		expect(have.has(Audit.built(kind)),"buildable: %s"%kind)
	for depth in range(1,Mines.MAX_DEPTH+1):
		expect(have.has(Audit.mine(depth)),"mine floor %d can be opened"%depth)
	expect(have.has(Audit.HOIST),"hoist can be repaired")
	for demand:Dictionary in Audit.demands():
		for item:String in demand.items:
			expect(have.has(item),"demand %s material is obtainable: %s"%[demand.id,item])
	# 不靠鈴幣也都拿得到嗎？（種子攤與田尾市集以外的來源）
	var no_coin:=[]
	for item in Audit.start_items():
		if item!=Audit.COIN:no_coin.append(item)
	var no_buy:=[]
	for entry:Dictionary in convs:
		if entry.kind!="buy":no_buy.append(entry)
	var frugal:Dictionary=Audit.reachable(no_buy,no_coin)
	expect(frugal.have.has(Audit.COIN),"coins can be earned without spending any")
	var needs_shop:=[]
	for item:String in World.NAMES:
		if item!="mill_kit" and not frugal.have.has(item):needs_shop.append(item)
	needs_shop.sort()
	print("ECON NOTE items that need a first purchase (%d): %s"%[needs_shop.size(),", ".join(needs_shop)])
	# 沒有起始背包（把起始種子與樹苗用光之後）也回得來。
	var empty_start:Dictionary=Audit.reachable(convs,[Audit.COIN,Audit.TIME])
	for item:String in World.NAMES:
		expect(empty_start.have.has(item)==(item!="mill_kit"),"acquisition rules after using the starter items: %s"%item)
	# 連鈴幣也花光：能再賺到鈴幣，全部都還拿得到。
	var broke:Dictionary=Audit.reachable(convs,[Audit.TIME])
	expect(broke.have.has(Audit.COIN),"a broke character can earn coins again")
	for item:String in World.NAMES:
		expect(broke.have.has(item)==(item!="mill_kit"),"acquisition rules with a broke character: %s"%item)

## 解鎖鏈：拿掉某一層的來源，後面該鎖的就要鎖起來（確認模型真的有依賴）。
func test_unlock_order(convs:Array) -> void:
	var start:=Audit.start_items()
	# 每一層工程的材料，在開那一層之前就拿得到。
	for depth in range(2,Mines.MAX_DEPTH+1):
		var limited:=[]
		for entry:Dictionary in convs:
			var blocked:=false
			for later in range(depth,Mines.MAX_DEPTH+1):
				if entry.id=="mine:%d"%later or entry.id=="drill:%d"%later:blocked=true
			if not blocked:limited.append(entry)
		var reach:Dictionary=Audit.reachable(limited,start)
		expect(reach.have.has(Audit.mine(depth)),"floor %d opens without anything mined on floor %d or deeper"%[depth,depth])
	# 第 5 層的晶砂是第 8 層玻璃燈罩工程的唯一來源：拿掉第 5 層採礦，第 9 層就開不了。
	var without_b5:=[]
	for entry:Dictionary in convs:
		if entry.id!="mine:5":without_b5.append(entry)
	var cut:Dictionary=Audit.reachable(without_b5,start)
	expect(not cut.have.has("glass") and cut.have.has(Audit.mine(8)) and not cut.have.has(Audit.mine(9)),"without floor 5 crystal sand there is no glass and floor 9 stays shut")
	expect(not cut.have.has(Audit.built("greenhouse_roof")) and not cut.have.has(Audit.built("fish_display")),"glass furniture depends on floor 5")
	# 沒有強化石鎬就沒有銅，銅接頭之後的東西都做不出來。
	var no_pick:=[]
	for entry:Dictionary in convs:
		if entry.id!="craft:reinforced_pick":no_pick.append(entry)
	cut=Audit.reachable(no_pick,start)
	expect(not cut.have.has("copper_ore") and not cut.have.has("copper_joint") and not cut.have.has(Audit.mine(1)),"no pick means no copper and no mine")
	expect(cut.have.has("gold_ore") and cut.have.has("gold_sample"),"gold panning still yields gold ore without a pick")
	expect(cut.have.has("plank") and cut.have.has("bread") and cut.have.has("tea_jar"),"wood, cooking and pottery do not need a pick")
	# 星夜菇只能種在第五層的菌床：沒有石鎬就沒有星夜菇，也做不出雪點鱒魚火鍋。
	expect(cut.have.has("star_mushroom_seed") and not cut.have.has("star_mushroom") and not cut.have.has("trout_hotpot"),"star mushrooms need the fifth mine floor")
	var no_b5_gate:=[]
	for entry:Dictionary in convs:
		if entry.id!="mine_open:5":no_b5_gate.append(entry)
	cut=Audit.reachable(no_b5_gate,start)
	expect(cut.have.has(Audit.mine(4)) and not cut.have.has(Audit.mine(5)) and not cut.have.has("star_mushroom") and cut.have.has("snow_trout") and not cut.have.has("trout_hotpot"),"without opening floor 5 there is no star mushroom and no trout hotpot")
	# 玻璃爐要先修升降台，升降台要先開到第 6 層。
	var no_hoist:=[]
	for entry:Dictionary in convs:
		if entry.id!="mine_hoist":no_hoist.append(entry)
	cut=Audit.reachable(no_hoist,start)
	expect(not cut.have.has(Audit.built("glass_furnace")) and cut.have.has("glass") and cut.have.has(Audit.mine(15)),"no hoist: no furnace, but workbench glass still reaches floor 15")
	expect(not cut.have.has("vein_quartz") or cut.fired.has("mine:9"),"vein quartz comes from floor 9 or 10")
	# 赭土仍只在第 6、7 層，玻璃爐改用鐵錠。
	var no_ochre:=[]
	for entry:Dictionary in convs:
		if entry.id not in ["mine:6","mine:7"]:no_ochre.append(entry)
	cut=Audit.reachable(no_ochre,start)
	expect(not cut.have.has("ochre_earth") and cut.have.has(Audit.built("glass_furnace")),"Ochre remains exclusive to floors 6 and 7; the furnace uses iron instead")
	expect(Audit.build_cost("glass_furnace")=={"stone":25,"iron_ingot":6},"Glass furnace requires the intended iron and stone")
	expect(Audit.sale_table().get("ochre_earth")==10,"Surplus ochre earth can be shipped for ten bells")

func test_certificate(convs:Array) -> void:
	var result:Dictionary=Audit.certificate(convs)
	expect(result.violations.is_empty(),"no conversion turns bought goods into more value: %s"%str(result.violations))
	expect(result.stable,"values settle (no loop that multiplies items or coins); rounds=%d"%int(result.rounds))
	var gaps:Array=Audit.certificate_gaps(convs,result.value)
	expect(gaps.is_empty(),"every untimed conversion is value-non-increasing: %s"%str(gaps))
	var value:Dictionary=result.value
	expect(is_equal_approx(float(value[Audit.COIN]),1.0),"a coin is worth one coin")
	var untimed:=0
	for entry:Dictionary in convs:
		if entry.timed:continue
		untimed+=1
		# 逐條再算一次（不經過 certificate_gaps）。
		var out_value:=0.0
		for item:String in entry.out:out_value+=float(value.get(item,0.0))*float(entry.out[item])
		var in_value:=0.0
		for item:String in entry["in"]:in_value+=float(value.get(item,0.0))*float(entry["in"][item])
		expect(out_value<=in_value+0.0001,"%s: out %.3f <= in %.3f"%[entry.id,out_value,in_value])
	expect(untimed>150,"the certificate covers the untimed conversions (%d)"%untimed)
	for item:String in value:
		expect(is_finite(float(value[item])) and float(value[item])>=0.0,"value of %s is finite"%item)
		if item!=Audit.COIN and not Audit.is_gate(item):
			expect(float(value[item])>=Audit.FLOOR-0.000001,"value of %s is positive"%item)
	# 買得到的東西，價值不超過買價；賣得掉的東西，價值不低於賣價。
	for item:String in result.caps:
		expect(float(value[item])<=float(result.caps[item])+0.0001,"%s is worth no more than its price"%item)
	for item:String in Audit.sale_table():
		expect(float(value[item])>=float(Audit.best_sale(item))-0.0001,"%s is worth at least its best sale"%item)
	print("ECON NOTE certificate rounds=%d untimed=%d"%[int(result.rounds),untimed])

## 把真實模型改壞一點，確認檢查會亮。
func test_counterfactuals(convs:Array) -> void:
	var c:=Audit.COIN
	# 糖在田尾賣 40；如果糖能以 50 出貨。
	var sugar:=convs.duplicate()
	sugar.append(Audit.conv("sell:sugar","sell",{"sugar":1},{c:50}))
	var result:Dictionary=Audit.certificate(sugar)
	expect(not result.stable and "sell:sugar" in ids_of(result.violations),"selling sugar above its shop price is caught")
	sugar[sugar.size()-1]=Audit.conv("sell:sugar","sell",{"sugar":1},{c:40})
	result=Audit.certificate(sugar)
	expect(result.stable and Audit.certificate_gaps(sugar,result.value).is_empty(),"selling sugar at its shop price is neutral")
	# 種子能以高於買價賣出。
	var seeds:=convs.duplicate()
	seeds.append(Audit.conv("sell:radish_seed","sell",{"radish_seed":1},{c:int(World.CROPS.radish.seed_price)+1}))
	result=Audit.certificate(seeds)
	expect(not result.stable and "sell:radish_seed" in ids_of(result.violations),"selling seeds above the stall price is caught")
	# 樹苗能賣 21（買 20）。
	var sapling:=convs.duplicate()
	sapling.append(Audit.conv("sell:sapling","sell",{"sapling":1},{c:Audit.SAPLING_PRICE+1}))
	result=Audit.certificate(sapling)
	expect(not result.stable,"selling saplings above the stall price is caught")
	# 蘭陽育苗 1 換 3：樹苗只要能賣 1 鈴幣，就會越換越多。
	sapling[sapling.size()-1]=Audit.conv("sell:sapling","sell",{"sapling":1},{c:1})
	result=Audit.certificate(sapling)
	expect(result.stable and Audit.certificate_gaps(sapling,result.value).is_empty(),"a 1-coin sapling is still covered by the fibre and wood the nursery takes")
	# 拆除多退一塊木材。
	var refund:=convs.duplicate()
	for index in refund.size():
		if refund[index].id=="remove:floor":refund[index]=Audit.conv("remove:floor","remove",{Audit.built("floor"):1},{"wood":3})
	result=Audit.certificate(refund,200)
	expect(not result.stable,"a demolition refund above the build cost is caught")
	# 木板能鋸回更多木材。
	var saw:=convs.duplicate()
	saw.append(Audit.conv("unsaw","process",{"plank":1},{"wood":3}))
	result=Audit.certificate(saw,200)
	expect(not result.stable,"plank -> 3 wood against 4 wood -> 2 planks is caught")
	saw[saw.size()-1]=Audit.conv("unsaw","process",{"plank":1},{"wood":2})
	result=Audit.certificate(saw)
	expect(result.stable and Audit.certificate_gaps(saw,result.value).is_empty(),"plank -> 2 wood is exactly neutral")
	# 待修陶罐不用陶土就能修好：罐子可以無限重複使用，但每次仍要一份茶，不是套利。
	var jar:=convs.duplicate()
	jar.append(Audit.conv("free_repair","tea",{"tea_spent_jar":1},{"tea_jar":1}))
	result=Audit.certificate(jar)
	expect(result.stable and Audit.certificate_gaps(jar,result.value).is_empty(),"free jar repair is still bounded by tea leaves")
	# 陶土能換回比原本更多的石材。
	jar[jar.size()-1]=Audit.conv("clay_to_stone","tea",{"clay":1},{"stone":3})
	result=Audit.certificate(jar,200)
	expect(not result.stable,"clay -> 3 stone against 2 stone -> clay is caught")
	var reach:Dictionary=Audit.reachable(convs,Audit.start_items())
	expect(reach.have.has("glass"),"glass is obtainable in the real model")

func test_seed_returns() -> void:
	var returns:Dictionary=Audit.seed_returns()
	expect(returns.size()==World.CROPS.size(),"every crop has a seed-return entry")
	var above_one:={}
	for seed_item:String in returns:
		var routes:Array=returns[seed_item]
		expect(not routes.is_empty(),"%s has a way back to seed"%seed_item)
		for route:Dictionary in routes:
			if route.via=="seed_maker":
				expect(float(route.ratio)<=1.0+0.000001,"seed machine returns at most one %s per packet planted (%.2f)"%[seed_item,float(route.ratio)])
			if float(route.ratio)>1.0+0.000001:above_one[seed_item+":"+str(route.via)]=float(route.ratio)
	expect(above_one.is_empty(),"no seed route multiplies packets: %s"%str(above_one))
	for kind:String in Flower.SEEDS:
		expect(Audit.best_sale(str(Flower.SEEDS[kind]))==0,"%s seed cannot be sold"%kind)
	print("ECON NOTE seed routes above 1.0: %s"%str(above_one))

func test_farming_and_prices() -> void:
	var prices:Dictionary=Audit.sale_table()
	for kind:String in World.CROPS:
		var crop:Dictionary=World.CROPS[kind]
		var lifetime:=int(crop.yield)*int(crop.get("cycles",1))
		expect(int(crop.seed_price)>0 and lifetime>0,"%s has a seed price and a harvest"%kind)
		if prices.has(kind):
			expect(lifetime*int(prices[kind])>=int(crop.seed_price),"growing %s to the end sells for at least the seed price (%d vs %d)"%[kind,lifetime*int(prices[kind]),int(crop.seed_price)])
		expect(not prices.has(kind+"_seed"),"%s seed has no sale price"%kind)
	for item:String in prices:
		expect(int(prices[item])>0,"%s sale price is positive"%item)
		expect(World.NAMES.has(item),"priced item exists: %s"%item)
	# 單品購買：買得到的東西都賣不掉。組合購買（如根菜組）：整組賣出的總收入必須低於購買價。
	for entry:Dictionary in Audit.conversions():
		if entry.kind!="buy":continue
		if entry.out.size()==1 and int(entry.out.values()[0])==1:
			for item:String in entry.out:
				expect(Audit.best_sale(item)==0,"bought item cannot be sold back: %s"%item)
			continue
		var revenue:=0
		for item:String in entry.out:revenue+=Audit.best_sale(item)*int(entry.out[item])
		var cost:=int(entry["in"].get(Audit.COIN,0))
		expect(cost>0 and revenue<cost,"bundle %s sale revenue %d is below purchase %d"%[entry.id,revenue,cost])

## 不算失敗、給平衡檢查看的清單。
func report(convs:Array) -> void:
	var losing:Array=Audit.losing_recipes()
	var lines:=[]
	for entry:Dictionary in losing:lines.append("%s %d->%d"%[entry.id,int(entry.in_sale),int(entry.out_sale)])
	lines.sort()
	print("ECON NOTE recipes selling for less than their ingredients (%d): %s"%[lines.size(),"; ".join(lines)])
	var prices:Dictionary=Audit.sale_table()
	var unsold:=[]
	for item:String in World.NAMES:
		if not prices.has(item) and not item.ends_with("_seed") and not item.ends_with("_kit"):unsold.append(item)
	unsold.sort()
	print("ECON NOTE items with no sale price (%d, seeds and kits omitted): %s"%[unsold.size(),", ".join(unsold)])
	var kinds:={}
	for entry:Dictionary in convs:kinds[entry.kind]=int(kinds.get(entry.kind,0))+1
	print("ECON NOTE conversions by kind: %s"%str(kinds))
