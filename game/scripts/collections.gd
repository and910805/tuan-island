extends RefCounted

const FISH := {
	"carp": {"name": "圓肚鯽魚", "price": 18},
	"minnow": {"name": "銀線溪魚", "price": 22},
	"redfish": {"name": "紅尾小鯉", "price": 28},
	"loach": {"name": "斑點泥鰍", "price": 24},
	"sardine":{"name":"藍背沙丁","price":26},
	"flounder":{"name":"奶油比目魚","price":46},
	"moon_squid":{"name":"月光小魷","price":52},
	"gold_shrimp":{"name":"金邊蝦","price":31},
	"glass_shrimp":{"name":"玻璃小蝦","price":36},
	"snow_trout":{"name":"雪點鱒魚","price":54},
	"bamboo_ayu":{"name":"竹影香魚","price":43},
	"star_spot":{"name":"星斑魚","price":62},
}

const FRESHWATER_FISH := ["carp","minnow","redfish","loach"]
const RARE_FISH_LIMIT := 20
const ANGLING_THRESHOLDS := [0,3,8,16,28,45,65,90,120,155]
const WATER_CLUES_LEVEL := 3
const FISHING_FORECAST_LEVEL := 6
const FISH_DISPLAY_LEVEL := 10
const COAST_DAY_START := 360
const COAST_NIGHT_START := 1200
const WanganCoast=preload("res://scripts/wangan_coast.gd")
const SHORE_FINDS:={
	WanganCoast.SHELL_ITEM:{"name":"潮紋貝殼","hint":"退潮時，到望安南岸沙灘撿拾。"},
	"seaweed":{"name":"海苔","hint":"沿南岸棧道往東，到岸邊採集。"},
}
const STORY_OBJECTS:={"gold_sample":"金工收藏樣本"}
const ResidentGoals=preload("res://scripts/resident_goals.gd")
const DISPLAY_CAP:=6
const GALLERY_ACTIONS:=["collection_donate","collection_display","collection_unshow"]

static func story_item(item:String)->bool:
	return STORY_OBJECTS.has(item) or ResidentGoals.is_keepsake_item(item)

static func kept_story_item(item:String,player:Dictionary)->bool:
	return ResidentGoals.is_keepsake_item(item) and ResidentGoals.keepsake_claimed(player,item.trim_suffix(ResidentGoals.KIT_SUFFIX))

static func story_catalog()->Dictionary:
	var catalog:=STORY_OBJECTS.duplicate()
	for kind:String in ResidentGoals.KEEPSAKE_ORDER:
		catalog[ResidentGoals.keepsake_item(kind)]=ResidentGoals.KEEPSAKES[kind].name
	return catalog

static func gallery_item(item:String,crops:Dictionary,recipes:Dictionary)->bool:
	return crops.has(item) or FISH.has(item) or SHORE_FINDS.has(item) or story_item(item) or (recipes.has(item) and is_meal(item))

static func gallery_valid(player:Dictionary,crops:Dictionary,recipes:Dictionary)->bool:
	var donations:Variant=player.get("collection_donations",{})
	var display:Variant=player.get("collection_display",[])
	if not donations is Dictionary or not display is Array or display.size()>DISPLAY_CAP:return false
	for record:Variant in [donations,player.get("collection_acquired",{})]:
		if not record is Dictionary:return false
		for item in record:
			if not item is String or not gallery_item(item,crops,recipes) or not record[item] is bool or not record[item]:return false
	var shown:Dictionary={}
	for item in display:
		if not item is String or not donations.has(item) or shown.has(item):return false
		shown[item]=true
	return true

static func note_acquisitions(player:Dictionary,previous:Dictionary,crops:Dictionary,recipes:Dictionary)->void:
	var record:Dictionary=player.get("collection_acquired",{})
	for item:String in player.inventory:
		var base:=item.trim_prefix("quality_") if crops.has(item.trim_prefix("quality_")) else item
		if gallery_item(base,crops,recipes) and int(player.inventory[item])>int(previous.get(item,0)):
			record[base]=true
	if not record.is_empty():player.collection_acquired=record

static func coast_is_day(minute:float) -> bool:
	return minute>=COAST_DAY_START and minute<COAST_NIGHT_START

static func fishing_forecast(region:String,person:Dictionary,minute:float) -> String:
	if region not in ["home","beimen"] or angling_level(person)<FISHING_FORECAST_LEVEL:return ""
	var is_day:=coast_is_day(minute)
	if region=="home":
		return "望安南岸 · 現在可釣藍背沙丁，20:00 後有機會釣到奶油比目魚。" if is_day else "望安南岸 · 今晚有機會釣到奶油比目魚，06:00 後以藍背沙丁為主。"
	var change:=COAST_NIGHT_START if is_day else COAST_DAY_START
	var hour:=change/60
	var next_day:="明日 " if not is_day and minute>=COAST_NIGHT_START else ""
	if is_day:
		return "預報 · 現在藍背沙丁；%s%02d:00 起，海岸留意比目魚、碼頭可釣小魷。"%[next_day,hour]
	return "預報 · 現在可遇比目魚或碼頭小魷；%s%02d:00 起可釣藍背沙丁。"%[next_day,hour]


static func angling_level(person:Dictionary) -> int:
	var catches:=int(person.get("fish_caught",0))
	for index in range(ANGLING_THRESHOLDS.size()-1,0,-1):
		if catches>=ANGLING_THRESHOLDS[index]:return index+1
	return 1

static func water_clues(region:String,person:Dictionary) -> String:
	if angling_level(person)<WATER_CLUES_LEVEL:return ""
	return {
		"home":"河灣橋可釣溪魚，南岸棧道外可釣藍背沙丁，夜間偶有奶油比目魚。",
		"lanyang":"宜蘭水圳 · 秋季或小雨天，成功釣魚可累積斑點泥鰍保底。",
		"beimen":"北門東岸 · 日間藍背沙丁，夜間奶油比目魚。"
	}.get(region,"")

const RARE_WATERS := {
	"lanyang":{"season":"autumn","fish":"loach","counter":"rare_fishing_misses","hint":"宜蘭水圳・秋季或小雨天"},
	"beimen":{"fish":"flounder","counter":"beimen_flounder_misses","hint":"北門海岸夜晚"},
	"jiaoxi":{"fish":"snow_trout","counter":"jiaoxi_trout_misses","hint":"礁溪高地冷泉・冬季"},
	"bamboo_grove":{"fish":"bamboo_ayu","counter":"bamboo_ayu_misses","hint":"霧竹溪谷・06:00–11:00"},
	"star_garden":{"fish":"star_spot","counter":"star_spot_misses","hint":"星芽庭園映星池・夜間"},
}

static func fishing_result(region:String,season:String,total:int,person:Dictionary,minute:=720.0,spot:="coast",raining:=false) -> Dictionary:
	if region=="home" and spot==WanganCoast.STAR_POOL_SPOT:return {"id":"gold_shrimp"}
	# Q05 河灣橋釣點 (opened with the bridge): its own catch, never the plain river rotation.
	if region=="home" and spot=="river_bridge_pool":return {"id":"redfish" if coast_is_day(minute) else "loach"}
	# D06 銀線溪魚淺灘 (beside the pool, opened with the bridge): the dependable minnow source for 香煎溪魚.
	if region=="home" and spot=="river_bridge_shoal":return {"id":"minnow"}
	if region=="home" and spot==WanganCoast.FISHING_SPOT:
		return {"id":"flounder" if not coast_is_day(minute) and total%5==4 else "sardine"}
	var water:Dictionary=RARE_WATERS.get(region,{})
	if region=="beimen":
		var day:=coast_is_day(minute)
		if spot=="tidepool":return {"id":"gold_shrimp"}
		if spot=="pier" and not day:return {"id":"moon_squid"}
		if day:return {"id":"sardine"}
	elif region=="jiaoxi":
		if spot=="spring" and coast_is_day(minute):return {"id":"glass_shrimp"}
		if spot!="upland" or season!="winter":return {"id":"minnow"}
	elif region=="bamboo_grove":
		if not preload("res://scripts/bamboo_grove.gd").breezy(minute):return {"id":"minnow"}
	elif region=="star_garden":
		if coast_is_day(minute):return {"id":"carp"}
	elif region!="lanyang" or (water.season!=season and not raining):
		return {"id":FRESHWATER_FISH[total%FRESHWATER_FISH.size()]}
	var misses:=int(person.get(water.counter,0))
	if misses+1>=RARE_FISH_LIMIT or total%23==22:
		return {"id":water.fish,"counter":water.counter,"misses":0}
	if region=="beimen":return {"id":"sardine","counter":water.counter,"misses":misses+1}
	if region in ["jiaoxi","bamboo_grove"]:return {"id":"minnow","counter":water.counter,"misses":misses+1}
	if region=="star_garden":return {"id":"carp","counter":water.counter,"misses":misses+1}
	var common:=FRESHWATER_FISH.duplicate()
	common.erase(water.fish)
	return {"id":common[total%common.size()],"counter":water.counter,"misses":misses+1}

const MILESTONES := {
	"garden_sampler": {
		"name": "菜園初收", "category": "crops", "target": 3,
		"reward_text": "60 鈴幣＋2 番茄種子", "coins": 60, "items": {"tomato_seed": 2},
	},
	"fish_survey": {
		"name": "島岸魚譜", "category": "fish", "target": 4,
		"reward_text": "100 鈴幣", "coins": 100, "items": {},
	},
	"kitchen_sampler": {
		"name": "島上家常菜", "category": "meals", "target": 3,
		"reward_text": "80 鈴幣＋2 胡蘿蔔種子", "coins": 80, "items": {"carrot_seed": 2},
	},
}

static func ensure_player(player: Dictionary) -> void:
	if not player.has("collection"):
		player.collection = {"crops": {}, "fish": {}, "meals": {}, "shore": {}, "claimed": {}}
	elif player.collection is Dictionary and not player.collection.has("shore"):
		player.collection.shore={}

static func is_meal(recipe_id: String) -> bool:
	# Flour is a mill product, never a stove meal (and never a collection entry).
	return recipe_id not in ["feed","flour","sugar"]

static func record(player: Dictionary, category: String, item_id: String) -> void:
	player.collection[category][item_id] = true

static func progress(player: Dictionary, milestone_id: String) -> int:
	if not MILESTONES.has(milestone_id):
		return 0
	var collection: Dictionary = player.get("collection", {})
	var discovered: Dictionary = collection.get(MILESTONES[milestone_id].category, {})
	return discovered.size()

static func validate(player: Dictionary, crops: Dictionary, recipes: Dictionary) -> bool:
	ensure_player(player)
	if not player.collection is Dictionary:
		return false
	var allowed := {"crops": crops, "fish": FISH, "meals": recipes, "shore": SHORE_FINDS, "claimed": MILESTONES}
	if player.collection.size() != allowed.size():
		return false
	for category in allowed:
		var entries = player.collection.get(category)
		if not entries is Dictionary or entries.size() > allowed[category].size():
			return false
		for item_id in entries:
			if not item_id is String or not allowed[category].has(item_id) or not entries[item_id] is bool or not entries[item_id]:
				return false
			if category == "meals" and not is_meal(item_id):
				return false
	for milestone_id in player.collection.claimed:
		if progress(player, milestone_id) < MILESTONES[milestone_id].target:
			return false
	return true
