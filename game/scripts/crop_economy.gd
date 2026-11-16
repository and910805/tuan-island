extends RefCounted
## T049／T093 作物成長與價格的一致性檢查與收益表。只給 tests/test_crop_economy*.gd 用，
## 遊戲流程不呼叫、不讀寫存檔。
##
## 做三件事：
##   1. plan_differences()：遊戲的 World.CROPS／CROP_SEASONS 與規劃書第 09 章作物表
##      （PLAN，手抄）逐欄比對。
##   2. row()／rows()：每種作物一包種子種到底的收成、淨收益、成長秒數與每小時淨收益。
##   3. recipe_rows()：每道料理「成品出貨價 − 材料出貨價」。
##
## 沒有算進去的：玩家整地、播種、澆水、採收與走路的時間（所以「每小時」是每格田
## 持續濕潤時的成長時間，不是玩家的工時）、灑水器與農機、午夜變乾、天氣、品質、
## 技能等級、市集主題日加價（另列 best_gross）、種子機回收種子、訂單與任務的獎勵。

const World=preload("res://scripts/world.gd")
const Weather=preload("res://scripts/weather.gd")
const Shipping=preload("res://scripts/shipping.gd")
const Audit=preload("res://scripts/economy_audit.gd")

## 規劃書第 09 章作物表（手抄；欄位：季節、成長天數、種子價、每次產量、售價）。
## 季節欄的「冬／溫室」記為冬，「全季／溫室」「洞內菌床」「茶圃」記為不分季節（空陣列）。
const PLAN:={
	"radish":{"name":"奶白蘿蔔","seasons":["spring","autumn"],"days":2,"seed":12,"yield":1,"price":24},
	"carrot":{"name":"糖心胡蘿蔔","seasons":["spring","autumn"],"days":3,"seed":20,"yield":1,"price":42},
	"lettuce":{"name":"圓葉萵苣","seasons":["spring","summer"],"days":2,"seed":14,"yield":1,"price":28},
	"potato":{"name":"小馬鈴薯","seasons":["spring","winter"],"days":4,"seed":25,"yield":2,"price":30},
	"strawberry":{"name":"蜜香草莓","seasons":["spring"],"days":5,"seed":70,"yield":2,"price":36},
	"cauliflower":{"name":"雲朵花椰菜","seasons":["spring","winter"],"days":5,"seed":45,"yield":1,"price":95},
	"tomato":{"name":"太陽番茄","seasons":["summer"],"days":4,"seed":55,"yield":2,"price":28},
	"cucumber":{"name":"波點黃瓜","seasons":["summer"],"days":3,"seed":40,"yield":2,"price":22},
	"sweet_corn":{"name":"甜玉米","seasons":["summer","autumn"],"days":5,"seed":60,"yield":2,"price":35},
	"watermelon":{"name":"小圓西瓜","seasons":["summer"],"days":6,"seed":65,"yield":1,"price":135},
	"pumpkin":{"name":"琥珀南瓜","seasons":["autumn"],"days":6,"seed":70,"yield":1,"price":150},
	"sweet_potato":{"name":"栗香地瓜","seasons":["autumn"],"days":4,"seed":32,"yield":2,"price":34},
	"eggplant":{"name":"紫絨茄子","seasons":["summer","autumn"],"days":4,"seed":48,"yield":2,"price":27},
	"wheat":{"name":"星點小麥","seasons":["spring","summer","autumn"],"days":3,"seed":18,"yield":2,"price":19},
	"rice":{"name":"月牙稻米","seasons":["summer","autumn"],"days":4,"seed":28,"yield":2,"price":29},
	"cabbage":{"name":"雪白高麗菜","seasons":["winter"],"days":5,"seed":44,"yield":1,"price":94},
	"sugar_beet":{"name":"霜糖甜菜","seasons":["winter"],"days":4,"seed":30,"yield":1,"price":66},
	"ginger":{"name":"暖泉薑","seasons":["winter"],"days":5,"seed":45,"yield":2,"price":48},
	"chime_herb":{"name":"風鈴香草","seasons":[],"days":3,"seed":24,"yield":1,"price":48},
	"cotton":{"name":"棉球花","seasons":["spring","summer"],"days":5,"seed":40,"yield":2,"price":42},
	"bluebell":{"name":"鈴蘭藍花","seasons":["spring"],"days":4,"seed":28,"yield":2,"price":28},
	"orange_blossom":{"name":"蜜橙花","seasons":["summer","autumn"],"days":4,"seed":28,"yield":2,"price":28},
	"star_mushroom":{"name":"星夜菇","seasons":[],"days":4,"seed":36,"yield":2,"price":36},
	"mist_tea":{"name":"霧竹茶","seasons":[],"days":5,"seed":65,"yield":2,"price":38},
}
## 規劃書第 09 章：再生作物為草莓、番茄、黃瓜、茄子與茶，共 3 次收成。
const PLAN_REGROW:=["strawberry","tomato","cucumber","eggplant","mist_tea"]
const PLAN_HARVESTS:=3
## 規劃書：再生作物首熟後每 2 天一次。遊戲的 CROPS[kind].regrow 是這 2 天換成的秒數（見 plan_schedule）。
const PLAN_REGROW_DAYS:=2
## 只能種在特定地方的作物（world.gd planting_problem，手抄）。
const PLACES:={"mist_tea":"bamboo_tea_beds","rice":"lanyang_paddy","star_mushroom":"mine_5"}

static func sorted_copy(values:Array) -> Array:
	var copy:=values.duplicate()
	copy.sort()
	return copy

static func lifetime(crop:Dictionary) -> int:
	return int(crop.get("yield",0))*int(crop.get("cycles",1))

## 一包種子種到底。profit 以出貨箱／種子攤的基本售價計；best_gross 是市集主題日的最高價。
static func row(kind:String,crops:Dictionary=World.CROPS,seasons:Dictionary=World.CROP_SEASONS) -> Dictionary:
	var crop:Dictionary=crops[kind]
	var cycles:=int(crop.get("cycles",1))
	var total:=lifetime(crop)
	var gross:=total*int(crop.price)
	var profit:=gross-int(crop.seed_price)
	var grow_seconds:=float(crop.time)+float(crop.get("regrow",crop.time))*float(cycles-1)
	var open:Array=seasons.get(kind,[])
	return {
		"kind":kind,"name":str(crop.name),"time":float(crop.time),"cycles":cycles,"yield":int(crop.get("yield",0)),
		"lifetime":total,"seed_price":int(crop.seed_price),"price":int(crop.price),"gross":gross,"profit":profit,
		"grow_seconds":grow_seconds,
		"profit_per_hour":float(profit)*3600.0/grow_seconds if grow_seconds>0.0 else 0.0,
		"roi":float(profit)/float(crop.seed_price) if int(crop.seed_price)>0 else 0.0,
		"seasons":sorted_copy(open),
		"days_open":Weather.DAYS_PER_SEASON*(Weather.SEASONS.size() if open.is_empty() else open.size()),
		"best_gross":total*Audit.best_sale(kind),
		"place":str(PLACES.get(kind,"")),
	}

static func rows(crops:Dictionary=World.CROPS,seasons:Dictionary=World.CROP_SEASONS) -> Array:
	var kinds:=sorted_copy(crops.keys())
	var list:=[]
	for kind:String in kinds:list.append(row(kind,crops,seasons))
	return list

## 遊戲資料與規劃書作物表不同的地方（每項一行文字）；空陣列表示逐欄相同。
static func plan_differences(crops:Dictionary=World.CROPS,seasons:Dictionary=World.CROP_SEASONS) -> Array:
	var lines:=[]
	for kind:String in sorted_copy(PLAN.keys()):
		if not crops.has(kind):
			lines.append("%s: in the plan, missing from the game"%kind)
			continue
		var plan:Dictionary=PLAN[kind]
		var crop:Dictionary=crops[kind]
		if str(crop.get("name",""))!=str(plan.name):lines.append("%s: name %s vs plan %s"%[kind,str(crop.get("name","")),str(plan.name)])
		if int(crop.get("seed_price",-1))!=int(plan.seed):lines.append("%s: seed price %d vs plan %d"%[kind,int(crop.get("seed_price",-1)),int(plan.seed)])
		if int(crop.get("yield",-1))!=int(plan["yield"]):lines.append("%s: yield %d vs plan %d"%[kind,int(crop.get("yield",-1)),int(plan["yield"])])
		if int(crop.get("price",-1))!=int(plan.price):lines.append("%s: price %d vs plan %d"%[kind,int(crop.get("price",-1)),int(plan.price)])
		var want:=PLAN_HARVESTS if kind in PLAN_REGROW else 1
		if int(crop.get("cycles",1))!=want:lines.append("%s: harvests %d vs plan %d"%[kind,int(crop.get("cycles",1)),want])
		if sorted_copy(seasons.get(kind,[]))!=sorted_copy(plan.seasons):lines.append("%s: seasons %s vs plan %s"%[kind,str(sorted_copy(seasons.get(kind,[]))),str(sorted_copy(plan.seasons))])
	for kind:String in sorted_copy(crops.keys()):
		if not PLAN.has(kind):lines.append("%s: in the game, missing from the plan"%kind)
	for kind:String in sorted_copy(seasons.keys()):
		if not crops.has(kind):lines.append("%s: has seasons but is not a crop"%kind)
	return lines

## 規劃書天數較少、遊戲成長秒數卻較長的作物對（[短天數作物, 長天數作物]）。
static func time_order_breaks(crops:Dictionary=World.CROPS) -> Array:
	var breaks:=[]
	var kinds:=sorted_copy(PLAN.keys())
	for a:String in kinds:
		for b:String in kinds:
			if not crops.has(a) or not crops.has(b):continue
			if int(PLAN[a].days)<int(PLAN[b].days) and float(crops[a].time)>float(crops[b].time):breaks.append([a,b])
	return breaks

## 每種作物「遊戲成長秒數 ÷ 規劃書天數」。
static func seconds_per_plan_day(crops:Dictionary=World.CROPS) -> Dictionary:
	var result:={}
	for kind:String in PLAN:
		if crops.has(kind):result[kind]=float(crops[kind].time)/float(PLAN[kind].days)
	return result

## 規劃書的再生節奏（首熟 days 天，之後每 2 天一次）換成天數，對照遊戲「每次重新長滿」
## 換成同一把尺（遊戲秒數 ÷ 該作物每個規劃日的秒數）。只列再生作物。
static func plan_schedule(crops:Dictionary=World.CROPS) -> Dictionary:
	var result:={}
	for kind:String in PLAN_REGROW:
		if not crops.has(kind):continue
		var days:=int(PLAN[kind].days)
		var cycles:=int(crops[kind].get("cycles",1))
		var per_day:=float(crops[kind].time)/float(days)
		result[kind]={"plan_days":days+PLAN_REGROW_DAYS*(PLAN_HARVESTS-1),"game_days":(float(crops[kind].time)+float(crops[kind].get("regrow",crops[kind].time))*float(cycles-1))/per_day}
	return result

## {季節:[作物…]}，另有 "all" 是不分季節的作物。
static func season_table(crops:Dictionary=World.CROPS,seasons:Dictionary=World.CROP_SEASONS) -> Dictionary:
	var table:={"all":[]}
	for season:String in Weather.SEASONS:table[season]=[]
	for kind:String in sorted_copy(crops.keys()):
		var open:Array=seasons.get(kind,[])
		if open.is_empty():
			table["all"].append(kind)
			continue
		for season in open:
			if table.has(str(season)):table[str(season)].append(kind)
	return table

## 每道料理：材料與成品的出貨價。priced=false 表示有材料或成品沒有售價（margin 無意義）。
static func recipe_rows(recipes:Dictionary=World.RECIPES,prices:Dictionary={}) -> Array:
	var table:Dictionary=prices if not prices.is_empty() else Shipping.prices(World.CROPS,World.FISH,World.OTHER_SALES)
	var list:=[]
	for id:String in sorted_copy(recipes.keys()):
		var recipe:Dictionary=recipes[id]
		var priced:=table.has(id)
		var in_sale:=0
		for item:String in recipe.ingredients:
			if not table.has(item):priced=false
			in_sale+=int(table.get(item,0))*int(recipe.ingredients[item])
		var out_sale:=int(table.get(id,0))*int(recipe["yield"])
		var seconds:=float(recipe.get("time",0.0))
		list.append({"id":id,"priced":priced,"in_sale":in_sale,"out_sale":out_sale,"margin":out_sale-in_sale,"time":seconds,
			"margin_per_minute":float(out_sale-in_sale)*60.0/seconds if priced and seconds>0.0 else 0.0})
	return list
