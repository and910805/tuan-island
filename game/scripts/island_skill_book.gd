extends RefCounted

const World=preload("res://scripts/world.gd")
const Collection=World.Collections

static func skills(person:Dictionary)->Array[Dictionary]:
	var exploration:=int(person.get("exploration_points",World.exploration_points(person)))
	return [
		entry("農耕","wheat",World.farming_level(person),int(person.get("harvests",0)),World.FARMING_LEVEL_THRESHOLDS,"次採收",[
			[World.SEED_MAKER_LEVEL,"種子機"],[World.MEDIUM_SPRINKLER_LEVEL,"中型灑水器"],[World.LARGE_SPRINKLER_LEVEL,"大型灑水器"],[World.MASTER_FARMING_LEVEL,"豐收花圃、成熟作物金光"]]),
		entry("採集","sapling",World.gathering_level(person),int(person.get("gathering_points",0)),World.GATHERING_LEVEL_THRESHOLDS,"次採集",[
			[World.SAPLING_RECOVERY_LEVEL,"回收自種的成熟樹苗"],[World.RESOURCE_MAP_LEVEL,"周邊資源標記"],[10,"森林工具外觀"]]),
		entry("手作","plank",World.crafting_level(person),int(person.get("crafting_points",0)),World.CRAFTING_LEVEL_THRESHOLDS,"點手作經驗",[
			[3,"16×16 格藍圖"],[World.BATCH_BUILD_LEVEL,"成片施工、工坊升級"],[10,"工匠署名牌、展示架"]]),
		entry("漁獵觀察","minnow",Collection.angling_level(person),int(person.get("fish_caught",0)),Collection.ANGLING_THRESHOLDS,"次釣獲",[
			[Collection.WATER_CLUES_LEVEL,"水域線索"],[Collection.FISHING_FORECAST_LEVEL,"釣點預報"],[Collection.FISH_DISPLAY_LEVEL,"島岸魚譜展示櫃"]]),
		entry("探索","compass",World.exploration_level(exploration),exploration,World.EXPLORATION_LEVEL_THRESHOLDS,"處地區",[
			[3,"返家路標"],[World.SUPPLY_BOX_LEVEL,"便攜補給箱"],[World.EXPEDITION_TENT_LEVEL,"探險紀念帳篷"]]),
	]

static func entry(title:String,icon:String,level:int,points:int,thresholds:Array,unit:String,unlocks:Array)->Dictionary:
	var capped:=level>=thresholds.size()
	return {"title":title,"icon":icon,"level":level,"points":points,"unit":unit,
		"previous":thresholds[level-1],"next":thresholds[level] if not capped else thresholds[-1],"unlocks":unlocks}
