extends RefCounted
## T093 經濟、配方與解鎖依賴檢查的模型。只給 tests/test_economy_audit.gd 與稽核用，
## 遊戲流程不呼叫、不讀寫存檔。
##
## 把「拿什麼換到什麼」寫成一張轉換表（conversions），再做三件事：
##   1. reachable()：從新角色的起始背包出發，哪些物品與解鎖拿得到（沒有來源的必要
##      材料、互相等待的解鎖都會留在拿不到的那一邊）。
##   2. certificate()：替每個物品找一個「價值」，讓所有不靠時間的轉換（工作台、料理、
##      加工、買、賣、建造與拆除…）都不會讓總價值變多。找得到就證明：不靠採集、種植、
##      釣魚、採礦、畜養這些要花時間的來源，沒有任何一組轉換可以憑空多出鈴幣或物品。
##   3. seed_returns()：一包種子種到底，再全部換回種子，會變成幾包。
##
## 資料來源：能直接讀常數的都讀常數（World.CRAFT／RECIPES／BUILD／CROPS／FISH／
## OTHER_SALES、Industry.PROCESS、SeedMaker.recipes、Mines.COSTS／ORES／YIELDS／finds、
## 各模組的成本表）。寫在動作程式裡、沒有常數表的規則（採集量、茶陶、種子攤的樹苗價…）
## 是照程式手抄的，逐條標了出處；那些規則改了，這裡要跟著改。
##
## 沒有建模的條件（都當作已滿足）：地區與車票、章節與居民任務的先後、技能等級、季節、
## 地塊權限、每日上限的確切數字。所以這裡通過不代表玩家「依序」一定走得到，只代表
## 材料與解鎖之間沒有死結；礦層工程、升降台、玻璃爐、工作站這幾條解鎖鏈有建模。

const World=preload("res://scripts/world.gd")
const Industry=preload("res://scripts/industry.gd")
const Shipping=preload("res://scripts/shipping.gd")
const Market=preload("res://scripts/market_stall.gd")
const SeedMaker=preload("res://scripts/seed_maker.gd")
const Mines=preload("res://scripts/mine_depths.gd")
const MineDrill=preload("res://scripts/mine_drill.gd")
const Forestry=preload("res://scripts/forestry.gd")
const Waterworks=preload("res://scripts/waterworks.gd")
const Bobo=preload("res://scripts/bobo_workshop.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const Salt=preload("res://scripts/salt_pan.gd")
const Livestock=preload("res://scripts/livestock.gd")
const Lanyang=preload("res://scripts/lanyang_life.gd")
const StationLife=preload("res://scripts/station_life.gd")
const Village=preload("res://scripts/village.gd")
const ChapterOne=preload("res://scripts/chapter_one.gd")
const PublicKitchen=preload("res://scripts/public_kitchen.gd")
const TableWarmer=preload("res://scripts/table_warmer.gd")
const Outlying=preload("res://scripts/outlying_commissions.gd")
const JinguashiRevisit=preload("res://scripts/jinguashi_revisit.gd")
const Jinguashi=preload("res://scripts/jinguashi.gd")
const GoldPanning=preload("res://scripts/gold_panning.gd")
const OreRoute=preload("res://scripts/ore_route.gd")
const Souvenir=preload("res://scripts/souvenir_exchange.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const Bond=preload("res://scripts/resident_bond.gd")

## 假物品：鈴幣、時間（任何要等、要走、有冷卻或每日上限的來源都吃一份），以及
## "@built:<種類>"、"@mine:<層>"、"@hoist" 這些解鎖。
const COIN:="@coin"
const TIME:="@time"
const HOIST:="@hoist"
const GARDEN_DONE:="@flower_garden"
const WORKSHOP_DONE:="@workshop_upgrade"
const PICK:="reinforced_pick"
const EPS:=0.000001
## certificate() 給每個真實物品的最低價值：讓「沒有價目的東西互相越換越多」也會被抓到。
const FLOOR:=0.01

## world.gd join()：新角色的背包與鈴幣（手抄）。
const START:={"wood":12,"stone":4,"fiber":10,"radish_seed":5,"lettuce_seed":3,"wheat_seed":3,"sapling":2}
## world.gd 種子攤 buy sapling（手抄，程式裡是寫死的 20）。
const SAPLING_PRICE:=20
## 回訪紀念物（各回訪模組完成時給一個，手抄）。
const MEMENTO_KITS:=["water_share_plaque_kit","mine_lantern_kit","tea_ware_kit","salt_basket_kit"]
## world.gd craft 的前置（手抄）：採掘機要先開到第 5 層、水力加工台要先開到第 4 層。
const CRAFT_NEEDS:={"mine_drill_kit":5,"waterworks_kit":4}

static func built(kind:String) -> String:
	return "@built:"+kind

static func mine(depth:int) -> String:
	return "@mine:%d"%depth

static func is_pseudo(item:String) -> bool:
	return item.begins_with("@")

## 解鎖本身沒有價值、也不會被消耗（只出現在 needs）。
static func is_gate(item:String) -> bool:
	return item==HOIST or item.begins_with("@mine:")

static func conv(id:String,kind:String,inputs:Dictionary,outputs:Dictionary,needs:Array=[],timed:bool=false) -> Dictionary:
	var taken:Dictionary=inputs.duplicate()
	if timed:taken[TIME]=1
	return {"id":id,"kind":kind,"in":taken,"out":outputs.duplicate(),"needs":needs.duplicate(),"timed":timed}

static func _add(target:Dictionary,item:String,amount:int) -> void:
	target[item]=int(target.get(item,0))+amount

static func sale_table() -> Dictionary:
	return Shipping.prices(World.CROPS,World.FISH,World.OTHER_SALES,true)

## 一個物品賣給系統最多能拿到的鈴幣：出貨箱價，或市集攤位在主題日的價（×1.3 進位）。
static func best_sale(item:String,prices:Dictionary={}) -> int:
	var table:Dictionary=prices if not prices.is_empty() else sale_table()
	if not table.has(item):return 0
	var base:int=int(table[item])
	var category:String=Market.category_of(item,table)
	if category.is_empty():return base
	var best:int=base
	for day_index in Market.THEMES.size():
		best=maxi(best,Market.price_for(base,category,day_index))
	return best

static func build_cost(kind:String) -> Dictionary:
	var cost:={}
	var entry:Dictionary=World.BUILD[kind]
	for key:String in entry:
		if key!="name":cost[key]=int(entry[key])
	return cost

## 全部的轉換。timed=true 的是要花時間的來源或一次性的獎勵，不列入 certificate()。
static func conversions() -> Array:
	var list:=[]
	var prices:=sale_table()
	# --- 工作台（world.gd craft）---
	for id:String in World.CRAFT:
		var recipe:Dictionary=World.CRAFT[id]
		var needs:=[built("bench")]
		if CRAFT_NEEDS.has(id):needs.append(mine(int(CRAFT_NEEDS[id])))
		list.append(conv("craft:"+id,"craft",recipe.ingredients,{id:int(recipe.yield)},needs))
	# --- 料理（world.gd RECIPES，石灶）---
	for id:String in World.RECIPES:
		var recipe:Dictionary=World.RECIPES[id]
		list.append(conv("cook:"+id,"cook",recipe.ingredients,{id:int(recipe.yield)},[built("stove")]))
	# --- 加工站（industry.gd PROCESS）與種子機（seed_maker.gd）---
	for id:String in Industry.PROCESS:
		var recipe:Dictionary=Industry.PROCESS[id]
		list.append(conv("process:"+id,"process",recipe.ingredients,{id:int(recipe.yield)},[built(str(recipe.station))]))
		if id in World.INDUSTRY.METAL_RECIPES:list.append(conv("smelter:"+id,"process",recipe.ingredients,{id:int(recipe.yield)},[built(World.INDUSTRY.SMELTER)]))
	var seed_recipes:Dictionary=SeedMaker.recipes(World.CROPS)
	for id:String in seed_recipes:
		var recipe:Dictionary=seed_recipes[id]
		list.append(conv("seed_maker:"+id,"process",recipe.ingredients,{id:int(recipe.yield)},[built("seed_maker")]))
	# --- 建造與拆除（拆除全額退回材料）---
	for kind:String in World.BUILD:
		var cost:=build_cost(kind)
		var needs:=[]
		if kind=="glass_furnace":needs.append(HOIST)
		if kind==Industry.DYE_TABLE:needs.append(GARDEN_DONE)
		if kind==Industry.ASSEMBLY_TABLE:needs.append(WORKSHOP_DONE)
		list.append(conv("build:"+kind,"build",cost,{built(kind):1},needs))
		list.append(conv("remove:"+kind,"remove",{built(kind):1},cost))
	# Kit and metal models return different materials, so each has its own node.
	var kit_cost:=World.KIT_SPRINKLER_COST.duplicate()
	kit_cost.erase("name")
	var kit_device:=built("sprinkler_kit")
	list.append(conv("build:sprinkler_kit","build",kit_cost,{kit_device:1}))
	list.append(conv("remove:sprinkler_kit","remove",{kit_device:1},kit_cost))
	list.append(conv("workshop_upgrade","unlock",{},{WORKSHOP_DONE:1},[built("bench")],true))
	for kind:String in Industry.assembly_items():
		var kit:String=Industry.assembly_items()[kind]
		var station:=built(kit)
		list.append(conv("assemble:"+kit,"craft",World.assembly_recipe(kind),{kit:1},[built(Industry.ASSEMBLY_TABLE)]))
		if kind==Industry.ANIMAL_COLLECTOR:continue
		list.append(conv("build:"+kit,"build",{kit:1},{station:1}))
		list.append(conv("remove:"+kit,"remove",{station:1},{kit:1}))
	# --- 用鈴幣買 ---
	for kind:String in World.CROPS:
		list.append(conv("buy:"+kind+"_seed","buy",{COIN:int(World.CROPS[kind].seed_price)},{kind+"_seed":1}))
	for item:String in Flower.MARKET_PRICES:
		list.append(conv("buy_tianwei:"+item,"buy",{COIN:int(Flower.MARKET_PRICES[item])},{item:1}))
	list.append(conv("buy:sapling","buy",{COIN:SAPLING_PRICE},{"sapling":1}))
	# --- 賣給系統 ---
	for item:String in prices:
		list.append(conv("sell:"+item,"sell",{item:1},{COIN:best_sale(item,prices)}))
	# --- 茶陶（tea_ceramics.gd，手抄）---
	list.append(conv("tea:clay","tea",{"stone":2},{"clay":1}))
	list.append(conv("tea:fire","tea",{"clay":2},{"tea_jar":1}))
	list.append(conv("tea:flower_pot","tea",{"clay":Tea.POT_CLAY},{"flower_pot":1},[],Tea.POT_SECONDS>0.0))
	list.append(conv("tea:repair","tea",{"clay":1,"tea_spent_jar":1},{"tea_jar":1}))
	for style:String in ["light","deep"]:
		var tea:String="tea_"+style
		list.append(conv("tea:roast_"+style,"tea",{"tea_leaf":2},{tea:1}))
		list.append(conv("tea:sell_%s_fiber"%style,"tea",{tea:1,"fiber":1},{COIN:Tea.price_for(style,"fiber")}))
		for jar:String in Tea.RETURN_ITEM:
			list.append(conv("tea:sell_%s_%s"%[style,jar],"tea",{tea:1,jar:1},{COIN:Tea.price_for(style,"jar"),str(Tea.RETURN_ITEM[jar]):1}))
	# --- 田尾留種與染料（flower_nursery.gd）---
	for kind:String in Flower.SEEDS:
		list.append(conv("flower_save:"+kind,"flower",{kind:Flower.save_flower_cost(kind)},{str(Flower.SEEDS[kind]):1}))
	list.append(conv("flower_dye","flower",Flower.DYE.ingredients,{str(Flower.DYE.item):int(Flower.DYE["yield"])}))
	# --- 其他不靠時間的轉換 ---
	list.append(conv("lanyang_nursery","other",Lanyang.NURSERY_COST,{"sapling":int(Lanyang.NURSERY_YIELD)}))
	list.append(conv("handcraft:rope","craft",{"fiber":World.ROPE_FIBER_COST},{"rope":1}))
	list.append(conv("bobo_sorting","other",{"gold_ore":int(Bobo.INPUT)},{"gold_sample":int(Bobo.OUTPUT)}))
	list.append(conv("waterworks","other",Waterworks.INPUTS,{"copper_joint":1},[built("waterworks")]))
	# --- 礦層工程與升降台（解鎖）---
	list.append(conv("mine_enter","unlock",{},{mine(1):1},[PICK],true))
	for depth in range(2,Mines.MAX_DEPTH+1):
		list.append(conv("mine_open:%d"%depth,"unlock",Mines.COSTS[depth-2],{mine(depth):1},[mine(depth-1)]))
	list.append(conv("mine_hoist","unlock",Mines.HOIST_COST,{HOIST:1},[mine(int(Mines.HOIST_DEPTH))]))
	# --- 要花時間的來源（world.gd 採集量為手抄）---
	list.append(conv("gather:tree","source",{},{"wood":6,"fiber":2,"sapling":1,"resin":1},[],true))
	list.append(conv("gather:planted_tree","source",{"sapling":1},{"wood":6,"fiber":2,"sapling":1,"resin":1,"hardwood":World.HARDWOOD_YIELD},[],true))
	list.append(conv("gather:rock","source",{},{"stone":5},[],true))
	list.append(conv("gather:grass","source",{},{"fiber":4},[],true))
	list.append(conv("gather:quarry","source",{},{"stone":6},[],true))
	list.append(conv("gather:copper_home","source",{},{"copper_ore":2},[PICK],true))
	list.append(conv("gather:copper_jinguashi","source",{},{"copper_ore":int(Jinguashi.YIELD)},[PICK],true))
	list.append(conv("gold_panning","source",{},{str(GoldPanning.ITEM):1},[],true))
	list.append(conv("ore_route","source",{},{COIN:int(OreRoute.PAY)},[],true))
	for depth in range(1,Mines.MAX_DEPTH+1):
		var out:={}
		_add(out,str(Mines.ORES[depth-1]),int(Mines.YIELDS[depth-1]))
		for find in Mines.finds(depth):_add(out,str(find),1)
		list.append(conv("mine:%d"%depth,"source",{},out,[mine(depth),PICK],true))
	for depth in range(1,MineDrill.OUTPUTS.size()+1):
		var output:Dictionary=MineDrill.OUTPUTS[depth-1]
		list.append(conv("drill:%d"%depth,"source",{"charcoal":1},{str(output.item):int(output.quantity)},[built("mine_drill"),mine(depth)],true))
	list.append(conv("forester","source",{"charcoal":1,"sapling":1},Forestry.OUTPUT,[built("forester")],true))
	for fish:String in World.FISH:
		list.append(conv("fish:"+fish,"source",{},{fish:1},[],true))
	for kind:String in World.CROPS:
		var crop:Dictionary=World.CROPS[kind]
		# 星夜菇只能種在金瓜石第五層的洞內菌床（world.gd planting_problem，手抄）。
		var farm_needs:=[mine(5)] if kind=="star_mushroom" else []
		var yield_per_seed:=int(crop.yield)*int(crop.get("cycles",1))
		list.append(conv("farm:"+kind,"source",{kind+"_seed":1},{kind:yield_per_seed},farm_needs,true))
		var cared:=World.CROP_CATALOG.CARE_TARGET
		list.append(conv("farm_quality:"+kind,"source",{kind+"_seed":cared},
			{kind:yield_per_seed*cared,World.CROP_CATALOG.QUALITY_PREFIX+kind:1},farm_needs,true))
	list.append(conv("chicken","source",{"feed":1},{"egg":1},[],true))
	list.append(conv("chicken_quality","source",{"feed":Livestock.BONUS_INTERVAL},
		{"egg":Livestock.BONUS_INTERVAL,"quality_egg":1},[],true))
	for animal:String in Livestock.ANIMALS:
		var product:=str(Livestock.ANIMALS[animal].item)
		list.append(conv("livestock:"+animal,"source",{"feed":1},{product:1},[],true))
		list.append(conv("livestock_quality:"+animal,"source",{"feed":Livestock.BONUS_INTERVAL},
			{product:Livestock.BONUS_INTERVAL,"quality_"+product:1},[],true))
	list.append(conv("tea:pick","source",{},{"tea_leaf":2},[],true))
	list.append(conv("tea:potter_gift","source",{},{"clay":2},[],true))
	list.append(conv("salt_pan","source",{},{"sea_salt":int(Salt.YIELD)},[],true))
	list.append(conv("flower_starter","source",{},Flower.STARTER,[],true))
	list.append(conv("shore:seaweed","source",{},{"seaweed":1},[],World.SEAWEED_REGROW_SECONDS>0.0))
	list.append(conv("shore:wangan_shell","source",{},{World.WANGAN_COAST.SHELL_ITEM:1},[],true))
	list.append(conv("woodland:acorn","source",{},{World.Squirrel.ACORN:1},[],true))
	list.append(conv("woodland:ornament","other",{World.Squirrel.ACORN:World.Squirrel.COST},{World.Squirrel.KIT:1}))
	list.append(conv("mine_survey","source",{},{"gold_sample":1},[],true))
	list.append(conv("starter_kit","source",ChapterOne.STARTER_COST,ChapterOne.STARTER_ITEMS,[],true))
	# --- 任務、訂單、委託（一次性或每日一次）---
	for resident:String in Village.QUESTS:
		var quests:Array=Village.QUESTS[resident]
		for index in quests.size():
			var quest:Dictionary=quests[index]
			var out:Dictionary=quest.get("reward",{}).duplicate()
			if int(quest.get("coins",0))>0:out[COIN]=int(quest.coins)
			var needs:=[]
			if quest.has("object"):needs.append(built(str(quest.object)))
			if quest.has("second_object"):needs.append(built(str(quest.second_object)))
			list.append(conv("quest:%s:%d"%[resident,index],"quest",quest.get("items",{}),out,needs,true))
	for order:Dictionary in Village.ORDERS:
		list.append(conv("order:"+str(order.id),"quest",order.items,{COIN:int(order.coins)},[],true))
	list.append(conv("flower_order","quest",Flower.ORDER,{COIN:int(Flower.ORDER_PAY)},[],true))
	list.append(conv("flower_garden","quest",Flower.GARDEN_NEEDS,{GARDEN_DONE:1},[],true))
	list.append(conv("salt_order","quest",Salt.ORDER,{COIN:int(Salt.ORDER_PAY)},[],true))
	for id:String in Outlying.DEFS:
		list.append(conv("outlying:"+id,"quest",Outlying.DEFS[id].needs,{COIN:int(Outlying.DEFS[id].reward_coins)},[],true))
	# --- 活動與故事給的擺設套件 ---
	for id:String in Souvenir.ENTRIES:
		list.append(conv("souvenir:"+id,"reward",{},{id+"_kit":1},[],true))
	for id:String in Goals.KEEPSAKES:
		list.append(conv("keepsake:"+id,"reward",{},{id+str(Goals.KIT_SUFFIX):1},[],true))
	for item:String in MEMENTO_KITS:
		list.append(conv("memento:"+item,"reward",{},{item:1},[],true))
	return list

## 會收走物品、但不在 conversions() 裡的需求（公共工程、交貨、送禮）。每一項的材料都
## 必須拿得到。
static func demands() -> Array:
	var list:=[]
	for index in World.DOCK_REPAIRS.size():
		list.append({"id":"dock_repair:%d"%index,"items":World.DOCK_REPAIRS[index]})
	list.append({"id":"bridge_fund","items":World.FUND_MATERIAL_PRICES})
	list.append({"id":"livestock_collector","items":Livestock.COLLECTOR_COST})
	list.append({"id":"install_egg_basket","items":{"egg_basket":1}})
	list.append({"id":"collector_bind","items":{"egg_basket":1}})
	list.append({"id":"eat_rice_ball","items":{"star_rice_ball":1}})
	list.append({"id":"drink_ginger_tea","items":{"ginger_tea":1}})
	list.append({"id":"table_warmer","items":TableWarmer.INSTALL_COST})
	list.append({"id":"lanyang_repair","items":Lanyang.REPAIR_COST})
	list.append({"id":"station_repair","items":StationLife.REPAIR_COST})
	list.append({"id":"salt_gate","items":Salt.GATE_NEEDS_EACH})
	# 鹽田水車與收鹽台不是用 build 擺的，是在北門鹽田裝上去（salt_pan.gd KITS）。
	var salt_kits:={}
	for slot:String in Salt.KITS:salt_kits[str(Salt.KITS[slot])]=1
	list.append({"id":"salt_machines","items":salt_kits})
	list.append({"id":"flower_garden","items":Flower.GARDEN_NEEDS})
	for pigment:String in Industry.FURNITURE_DYES:
		list.append({"id":"dye_furniture:"+pigment,"items":{pigment:1}})
	list.append({"id":"public_kitchen","items":PublicKitchen.REQUIREMENTS})
	list.append({"id":"jinguashi_revisit","items":JinguashiRevisit.AMOUNTS})
	list.append({"id":"tea_revisit","items":{"tea_light":1,"tea_deep":1}})
	list.append({"id":"salt_revisit","items":{"sea_salt":1}})
	var gifts:={}
	for item:String in Bond.COMMON_GIFTS:gifts[item]=1
	list.append({"id":"resident_gifts","items":gifts})
	list.append({"id":"aru_bench_repair","items":World.RESIDENT_GOALS.cost(World.RESIDENT_GOALS.goal("aru",2),"")})
	list.append({"id":"lingpopo_memorial_bell","items":World.RESIDENT_GOALS.cost(World.RESIDENT_GOALS.goal("lingpopo",3),"soup")})
	return list

## 從 start（物品 ID 陣列）出發，反覆套用拿得到材料與解鎖的轉換，直到不再增加。
## 回傳 {"have":{物品:true},"fired":{轉換 id:true},"rounds":輪數}。
static func reachable(convs:Array,start:Array) -> Dictionary:
	var have:={}
	for item in start:have[str(item)]=true
	var fired:={}
	var rounds:=0
	var changed:=true
	while changed:
		changed=false
		rounds+=1
		for entry:Dictionary in convs:
			if fired.has(entry.id):continue
			var ready:=true
			for item:String in entry["in"]:
				if not have.has(item):
					ready=false
					break
			if ready:
				for item in entry.needs:
					if not have.has(str(item)):
						ready=false
						break
			if not ready:continue
			fired[entry.id]=true
			changed=true
			for item:String in entry.out:have[item]=true
	return {"have":have,"fired":fired,"rounds":rounds}

static func start_items() -> Array:
	var items:=[COIN,TIME]
	for item:String in START:items.append(item)
	return items

static func _total(amounts:Dictionary,value:Dictionary) -> float:
	var total:=0.0
	for item:String in amounts:
		total+=float(value.get(item,0.0))*float(amounts[item])
	return total

## 找一組價值 value（鈴幣固定為 1、其他物品 >= FLOOR），讓每個 timed=false 的轉換
## 「產出的總價值 <= 投入的總價值」。作法：從最低價值開始，哪個轉換產出比投入值錢，就把
## 投入的價值往上調（用鈴幣買得到的東西不超過買價）；調到都不用再調為止。
## 回傳 {"value","caps","stable","rounds","violations"}。violations 是「投入全部買得到、
## 買價加起來卻低於產出價值」的轉換——真正的套利候選。stable=false 表示價值一直往上漲，
## 也就是有一圈轉換越換越多。
static func certificate(convs:Array,max_rounds:int=400) -> Dictionary:
	var value:={COIN:1.0}
	var caps:={}
	var pure:=[]
	for entry:Dictionary in convs:
		if entry.timed:continue
		pure.append(entry)
		for group:String in ["in","out"]:
			for item:String in entry[group]:
				if item!=COIN and not is_gate(item) and not value.has(item):value[item]=FLOOR
		if entry.kind=="buy":
			for item:String in entry.out:
				var unit:=float(entry["in"][COIN])/float(entry.out[item])
				caps[item]=minf(float(caps.get(item,INF)),unit)
	var violations:=[]
	var stable:=false
	var rounds:=0
	while rounds<max_rounds and not stable:
		rounds+=1
		stable=true
		violations=[]
		for entry:Dictionary in pure:
			if entry.kind=="buy":continue
			var out_value:=_total(entry.out,value)
			var in_value:=_total(entry["in"],value)
			var need:=out_value-in_value
			if need<=EPS:continue
			var free:=[]
			var capped:=[]
			for item:String in entry["in"]:
				if item==COIN or is_gate(item):continue
				if caps.has(item):capped.append(item)
				else:free.append(item)
			if not free.is_empty():
				var weight:=0.0
				for item:String in free:weight+=float(value[item])*float(entry["in"][item])
				for item:String in free:
					var quantity:=float(entry["in"][item])
					var share:=need*(float(value[item])*quantity/weight) if weight>0.0 else need/float(free.size())
					value[item]=float(value[item])+share/quantity
				stable=false
				continue
			for item:String in capped:
				if need<=EPS:break
				var quantity:=float(entry["in"][item])
				var room:=(float(caps[item])-float(value[item]))*quantity
				if room<=EPS:continue
				var used:=minf(room,need)
				value[item]=float(value[item])+used/quantity
				need-=used
				stable=false
			if need>EPS:
				violations.append({"id":entry.id,"in_value":_total(entry["in"],value),"out_value":out_value})
	return {"value":value,"caps":caps,"stable":stable and violations.is_empty(),"rounds":rounds,"violations":violations}

## 獨立複核：拿 certificate() 的 value 重新算一次每個 timed=false 的轉換（含買），
## 回傳產出比投入值錢的那些。空陣列才算證明成立。
static func certificate_gaps(convs:Array,value:Dictionary) -> Array:
	var gaps:=[]
	for entry:Dictionary in convs:
		if entry.timed:continue
		var out_value:=_total(entry.out,value)
		var in_value:=_total(entry["in"],value)
		if out_value>in_value+EPS*maxf(1.0,in_value):
			gaps.append({"id":entry.id,"in_value":in_value,"out_value":out_value})
	return gaps

## 一包種子種到底的收成，全部換回種子會有幾包：{種子:[{"via","ratio"}]}。
## 種子機與田尾留種台都使用整株收成換一包。
static func seed_returns() -> Dictionary:
	var result:={}
	var machine:Dictionary=SeedMaker.recipes(World.CROPS)
	for kind:String in World.CROPS:
		var crop:Dictionary=World.CROPS[kind]
		var lifetime:=int(crop.yield)*int(crop.get("cycles",1))
		var seed_item:String=kind+"_seed"
		var routes:=[]
		if machine.has(seed_item):
			var recipe:Dictionary=machine[seed_item]
			routes.append({"via":"seed_maker","ratio":float(lifetime)*float(recipe.yield)/float(recipe.ingredients[kind])})
		if Flower.SEEDS.has(kind):routes.append({"via":"flower_save","ratio":float(lifetime)/Flower.save_flower_cost(kind)})
		result[seed_item]=routes
	return result

## 料理、加工、工作台裡「產出賣價低於材料賣價」的配方（只算材料全部有賣價的）。
## 不是錯誤（成品可能另有用途），列出來給平衡檢查看。
static func losing_recipes() -> Array:
	var prices:=sale_table()
	var result:=[]
	for entry:Dictionary in conversions():
		if entry.kind not in ["craft","cook","process"]:continue
		var in_sale:=0
		var all_priced:=true
		for item:String in entry["in"]:
			var price:=best_sale(item,prices)
			if price<=0:all_priced=false
			in_sale+=price*int(entry["in"][item])
		if not all_priced:continue
		var out_sale:=0
		for item:String in entry.out:out_sale+=best_sale(item,prices)*int(entry.out[item])
		if out_sale>0 and out_sale<in_sale:result.append({"id":entry.id,"in_sale":in_sale,"out_sale":out_sale})
	return result
