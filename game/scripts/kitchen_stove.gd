extends RefCounted

const SummerMarket = preload("res://scripts/summer_market.gd")
const ForestMushroom = preload("res://scripts/forest_mushroom_commission.gd")
## C12 公共廚房灶台 + D01-D16 canonical dishes (content bible §03 / §11).
##
## Station: type `kitchen_stove`, a fixed 2x2 (Industry.KITCHEN_STOVE). It is a normal private house
## stove AND may be donated to the Q04 public kitchen through the existing register / contribute
## actions. The early 1x1 `stove` is NOT replaced: its id, World.RECIPES numbers, saved `job` /
## `cooking` records and the picnic / tutorial route are untouched.
##
## Shared recipe logic. A queue record is an authoritative snapshot (ingredients / yield / duration are
## stored when the job is queued) and its `kind` is also the output item id. So one dish keeps ONE id
## (the existing item) and the two stove kinds simply read different tables:
##   - legacy `stove`   -> legacy_recipes(World.RECIPES): the old numbers, minus the dishes that only
##                         exist from C12 on (EXCLUSIVE);
##   - `kitchen_stove`  -> recipes(World.RECIPES): the same table with every D01-D16 entry replaced by
##                         its canonical ingredients / seconds / yield below.
## A distinct id exists only where there was no dish at all (D05 forest_mushroom_soup, D14
## rainbow_skewer). World.RECIPES holds both so names, tables, gifts, saves and the almanac stay one
## registry; stove_recipes() is what decides where they can be cooked.
##
## This script never preloads World (world.gd preloads it).

const KIND := "kitchen_stove"
const PART_FIELD := "kitchen_stove_part"
const CELLS := [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]
const NAME := "公共廚房灶台"
## C12: 石材 20、木材 12、陶土 5.
const COST := {"stone":20, "wood":12, "clay":5}
const STAMINA_CAP := 100
const EAT_ACTION := "eat_meal"
## Dishes whose eating (and 8-minute highland warmth for tea) already ships through the older actions
## `eat_rice_ball` / `drink_ginger_tea`; their tests and saves keep that exact path.
const LEGACY_EAT := ["star_rice_ball", "ginger_tea"]
## Dishes that did not exist before C12: the early stove cannot cook them.
const EXCLUSIVE := ["forest_mushroom_soup", "rainbow_skewer"]

## D01..D16 in spec order. `restore` = exploration stamina per serving eaten (cap 100, never
## overflows). `source` names the true acquisition route of the dish for the UI.
const DISHES := [
	{"dish":"D01", "id":"soup", "name":"熱蘿蔔湯", "ingredients":{"radish":2}, "time":30.0, "yield":2, "restore":20, "source":"公共廚房"},
	{"dish":"D02", "id":"baked_potato", "name":"烤馬鈴薯", "ingredients":{"potato":2}, "time":30.0, "yield":2, "restore":25, "source":"公共廚房"},
	{"dish":"D03", "id":"salad", "name":"菜園沙拉", "ingredients":{"lettuce":1, "tomato":1}, "time":30.0, "yield":2, "restore":20, "source":"夏季種子開放"},
	{"dish":"D04", "id":"bread", "name":"小麥麵包", "ingredients":{"flour":1}, "time":30.0, "yield":1, "restore":30, "source":"公共廚房；磨坊前可向商店買少量麵粉"},
	{"dish":"D05", "id":"forest_mushroom_soup", "name":"森林菇湯", "ingredients":{"star_mushroom":2, "chime_herb":1}, "time":60.0, "yield":2, "restore":35, "source":"菌床與森林委託"},
	{"dish":"D06", "id":"salt_grilled_fish", "name":"香煎溪魚", "ingredients":{"minnow":1, "sea_salt":1}, "time":60.0, "yield":1, "restore":40, "source":"河灣橋與海岸步道"},
	{"dish":"D07", "id":"corn_chowder", "name":"玉米濃湯", "ingredients":{"sweet_corn":2, "milk":1}, "time":90.0, "yield":3, "restore":30, "source":"領養奶糖牛"},
	{"dish":"D08", "id":"star_rice_ball", "name":"星點飯糰", "ingredients":{"rice":2, "seaweed":1}, "time":60.0, "yield":3, "restore":25, "source":"水田解鎖"},
	{"dish":"D09", "id":"strawberry_toast", "name":"草莓吐司", "ingredients":{"bread":2, "strawberry_jam":1}, "time":30.0, "yield":2, "restore":30, "source":"果醬鍋"},
	{"dish":"D10", "id":"pumpkin_pie", "name":"南瓜派", "ingredients":{"pumpkin":1, "flour":1, "egg":1}, "time":120.0, "yield":4, "restore":35, "source":"秋季種子開放"},
	{"dish":"D11", "id":"tea_pudding", "name":"茶香布丁", "ingredients":{"mist_tea":1, "milk":1, "egg":1}, "time":120.0, "yield":3, "restore":30, "source":"茶茶熟悉事件"},
	{"dish":"D12", "id":"ginger_tea", "name":"暖薑茶", "ingredients":{"ginger":1, "sugar":1}, "time":60.0, "yield":2, "restore":20, "source":"暖泉高地"},
	{"dish":"D13", "id":"seafood_rice", "name":"海鮮燉飯", "ingredients":{"rice":2, "gold_shrimp":1, "minnow":1}, "time":120.0, "yield":3, "restore":45, "source":"阿潮信任事件"},
	{"dish":"D14", "id":"rainbow_skewer", "name":"彩虹蔬菜串", "ingredients":{"radish":1, "carrot":1, "eggplant":1}, "time":60.0, "yield":3, "restore":25, "source":"夏季市集"},
	{"dish":"D15", "id":"garden_cookie", "name":"花園餅乾", "ingredients":{"flour":1, "sugar":1, "chime_herb":1}, "time":90.0, "yield":4, "restore":20, "source":"星禾熟悉事件"},
	{"dish":"D16", "id":"trout_hotpot", "name":"糰糰火鍋", "ingredients":{"cabbage":1, "star_mushroom":2, "snow_trout":1}, "time":180.0, "yield":4, "restore":50, "source":"風鈴節籌備"},
]

## D16 糰糰火鍋 (source "風鈴節籌備"). The festival preparation that unlocks it on the C12 stove is the
## six public island projects (World.island_project_mask() == ISLAND_NOTES.project_mask()), the very list
## the opening-night checklist shows. Those flags never un-set, so the unlock is DERIVED, not stored: no
## save field, no migration. `festival_story_open` (opening night, set once, permanent) also unlocks, so a
## world that already opened the festival is never locked out and later seasons keep it.
## Only the 2x2 stove is gated: the early one-cell stove keeps its old recipe table and behaviour, and
## jobs already queued / ready are never touched (the gate is read only when a new job is queued).
const FESTIVAL_DISH := "trout_hotpot"
const LOCKED_MESSAGE := "糰糰火鍋要等風鈴節籌備：完成六項公共工程後，才能在公共廚房灶台煮。"
const LOCKED_BUTTON := "風鈴節籌備後解鎖"
const LOCKED_TIP := "（風鈴節籌備後解鎖）"

## True when `dish` on a stove of type `stove_kind` waits for the festival preparation.
static func festival_gated(stove_kind: String, dish: String) -> bool:
	return stove_kind == KIND and dish == FESTIVAL_DISH

## C12 personal recipes (D11 / D15). They unlock for the player who actually finished the resident's
## 熟悉 event (ResidentGoals.done(person, resident).has(stage)); it is per player, derived, never stored.
## Only the 2x2 stove is gated: the early stove keeps its old table (tea_leaf pudding, old cookie) and
## jobs already queued / ready are never touched (the gate is read only when a new job is queued).
## D13 海鮮燉飯 keeps its own older rule (World.has_recipe, 阿潮 event 3), which covers both stoves.
const EVENT_GATES := {
	"tea_pudding":{"resident":"chacha", "stage":2,
		"message":"茶香布丁要先完成茶茶的熟悉事件〈漏下來的一束光〉：到貓空茶亭檢查三幅遮簾，交 8 份竹材和 2 塊布料，才能在公共廚房灶台煮。",
		"button":"完成茶茶〈漏下來的一束光〉後解鎖",
		"tip":"（完成茶茶的熟悉事件〈漏下來的一束光〉：貓空茶亭交 8 竹材、2 布料）"},
	"garden_cookie":{"resident":"xinghe", "stage":2,
		"message":"花園餅乾要先完成星禾的熟悉事件〈空花圃的圖紙〉：到蘭陽找星禾，選兩種花各帶 2 朵，才能在公共廚房灶台煮。",
		"button":"完成星禾〈空花圃的圖紙〉後解鎖",
		"tip":"（完成星禾的熟悉事件〈空花圃的圖紙〉：蘭陽交兩種花各 2 朵）"},
}

## The one lock rule of the C12 stove: {} when `dish` is free on `stove_kind`, else
## {"kind":"festival"|"event", "message", "button", "tip"[, "resident", "stage"]}.
static func gate(stove_kind: String, dish: String) -> Dictionary:
	if stove_kind != KIND:return {}
	if dish == FESTIVAL_DISH:
		return {"kind":"festival", "message":LOCKED_MESSAGE, "button":LOCKED_BUTTON, "tip":LOCKED_TIP}
	if EVENT_GATES.has(dish):
		var entry: Dictionary = (EVENT_GATES[dish] as Dictionary).duplicate()
		entry["kind"] = "event"
		return entry
	if dish == SummerMarket.DISH:return SummerMarket.gate_entry()
	if dish == ForestMushroom.DISH:return {"kind":"forest","message":ForestMushroom.COOKING_LOCK,"button":ForestMushroom.COOKING_BUTTON,"tip":ForestMushroom.COOKING_LOCK}
	return {}

## Pure rule shared by host and client. `festival_ready` is the D16 fact, `event_done` whether the gate's
## resident event is completed (only read for event gates). A dish without a gate is never locked.
static func locked(stove_kind: String, dish: String, festival_ready: bool, event_done: bool) -> bool:
	var g: Dictionary = gate(stove_kind, dish)
	if g.is_empty():return false
	return not (festival_ready if g.kind == "festival" else event_done)

## Pure rule. `source` is the world state (host) or a client snapshot; both carry `festival_story_open`.
## `projects` is the island project bitmask now, `required` the full mask. Never true for an empty mask.
static func festival_prep_done(source: Dictionary, projects: int, required: int) -> bool:
	var opened: Variant = source.get("festival_story_open", false)
	if typeof(opened) == TYPE_BOOL and opened:return true
	return required > 0 and (projects & required) == required

## The two dishes that are brand new items (the rest reuse existing recipe ids).
static func new_item_recipes() -> Dictionary:
	var out := {}
	for entry: Dictionary in DISHES:
		if entry.id in EXCLUSIVE:out[entry.id] = recipe_of(entry)
	return out

static func recipe_of(dish: Dictionary) -> Dictionary:
	return {"name":dish.name, "ingredients":(dish.ingredients as Dictionary).duplicate(), "time":float(dish.time), "yield":int(dish.yield)}

static func dish(item: String) -> Dictionary:
	for entry: Dictionary in DISHES:
		if entry.id == item:return entry
	return {}

static func is_dish(item: String) -> bool:
	return not dish(item).is_empty()

## Stamina restored by one eaten serving of `item`, 0 when it is not a D01-D16 dish.
static func restore_for(item: String) -> int:
	return int(dish(item).get("restore", 0))

## Early stove: `base` (World.RECIPES) without the C12-only dishes. Fresh deep copy.
static func legacy_recipes(base: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for item: String in EXCLUSIVE:out.erase(item)
	return out

## The C12 cookbook uses the D01–D16 names and quantities. Other recipes keep their existing entries.
static func recipes(base: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for entry: Dictionary in DISHES:
		out[entry.id] = recipe_of(entry)
	return out

## Recipe table for a stove object type.
static func recipes_for(kind: String, base: Dictionary) -> Dictionary:
	return recipes(base) if kind == KIND else legacy_recipes(base)

## [anchor + offset] cells of a stove whose anchor is `anchor`.
static func cells_at(anchor: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for offset: Vector2i in CELLS:out.append(anchor + offset)
	return out
