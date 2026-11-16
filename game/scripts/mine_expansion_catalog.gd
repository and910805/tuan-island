extends RefCounted
## T067 mine expansion catalog: depths B6–B15 of the 金瓜石 cooperative mine.
##
## Pure data + static lookups. Wired in (T067 integration): mine_depths.gd copies
## ore/yield/commission costs and reads energy_multiplier/finds; mine_layout.gd reads
## layout_template; mine_survey.gd reads survey pages; mine_ui.gd shows zones, hazards
## and commission titles. HISTORY_NOTES and PROPOSED_ITEMS remain unused on purpose.
## Deep-mine quest sources (Q07): B6/B7 finds add ochre_earth 赭土 (glass furnace
## build cost) and B9/B10 add vein_quartz 脈石英 (glass furnace crystal_sand recipe).
## B12/B13 add warm_stone 暖岩片 (shared-meal-table warmer, table_warmer.gd).
##
## Two layers that must never be mixed:
##   * Gameplay geology (zones, hazards, ores per depth, B6–B15 themselves) is
##     FICTIONAL. The game already labels the mine 「合作礦場為架空場景」 (mine_ui.gd).
##   * HISTORY_NOTES hold documented regional history about the real Jinguashi area.
##     They are paraphrases that still need a source check, so `display_ok` is false
##     until someone verifies them against the history_ui.gd sources page.
##   Depth text must not cite years, companies or real tunnel names (test-enforced).
##
## Existing item IDs only: every material in ORE/FINDS/COMMISSIONS/survey icons is a
## key of World.NAMES. Brand-new resources live in PROPOSED_ITEMS and are never
## required by an exit or a commission.
##
## No combat: hazards are environmental pacing (mine_energy drain multiplier) only.

const FIRST_NEW_DEPTH := 6
const MAX_DEPTH := 15
const SURFACE := "jinguashi"
## Hoist cage station on new depths; inside mine_layout.BASE_RECT, clear of
## mine_depths ENTRY/UP/DOWN/REST/SERVICE/NODES/POOL and the (12,20) protected cell.
const LIFT := Vector2i(17,17)
## Surface hoist may only lower players to these landings (≤ unlocked depth), and
## only after the shared Q07 hoist repair (mine_depths.surface_landings).
const LIFT_LANDINGS := [6,10,15]
const MAX_ENERGY_MULTIPLIER := 1.5

## Mirror of what B1–B5 already ship (mine_depths.gd / mine_survey.gd). The test
## cross-checks this against the live constants so drift is caught.
const EXISTING := {
	1:{"zone":"shallow_works","ore":"stone"},
	2:{"zone":"shallow_works","ore":"copper_ore"},
	3:{"zone":"shallow_works","ore":"stone"},
	4:{"zone":"shallow_works","ore":"copper_ore"},
	5:{"zone":"shallow_works","ore":"gold_ore"},
}

const ZONES := {
	"shallow_works":{"name":"淺層工作帶","depths":[1,5],"fiction":"gameplay_geology",
		"summary":"既有五層：木板支撐、抽水工程與第五層菌床。"},
	"rust_vein":{"name":"鏽紋銅脈帶","depths":[6,8],"fiction":"gameplay_geology",
		"summary":"岩壁帶紅褐鏽紋，銅礦與石材交錯，是加固木作的練習區。"},
	"seep_geode":{"name":"滲泉晶洞帶","depths":[9,11],"fiction":"gameplay_geology",
		"summary":"地下水從岩縫慢慢滲出，晶洞裡積著細晶砂，需要排水與照明。"},
	"warm_rock":{"name":"暖岩深脈帶","depths":[12,14],"fiction":"gameplay_geology",
		"summary":"岩面摸起來微溫，含金礦料較多，通道窄，休息節奏更重要。"},
	"lantern_hall":{"name":"提燈大廳","depths":[15,15],"fiction":"gameplay_geology",
		"summary":"最深處的寬敞洞廳，大家把提燈掛在這裡，是礦道的終點與聚會處。"},
}

## Non-combat environmental pacing. Mitigation always uses the existing rest station.
const HAZARDS := {
	"none":{"name":"平穩","energy_multiplier":1.0,"note":"空氣流通，照常作業。"},
	"drip":{"name":"滴水","energy_multiplier":1.1,"note":"頂上滴水，走慢一點；記得到休息站喝水。"},
	"loose_gravel":{"name":"碎石坡","energy_multiplier":1.1,"note":"坡面碎石多，沿木板走道移動。"},
	"low_ceiling":{"name":"矮頂","energy_multiplier":1.2,"note":"需要彎腰前進，體力消耗略增。"},
	"seep":{"name":"滲水","energy_multiplier":1.2,"note":"地面濕滑，記得在休息站補充體力。"},
	"mist":{"name":"水霧","energy_multiplier":1.2,"note":"視線較短，路牌加掛提燈。"},
	"warm_air":{"name":"暖空氣","energy_multiplier":1.3,"note":"空氣溫暖，休息站多放了水壺。"},
	"narrow":{"name":"窄縫","energy_multiplier":1.4,"note":"通道狹窄，側身慢慢通過；可隨時搭升降台回地面。"},
}

## New resources that do NOT exist in World.NAMES yet. Never required for exits
## or commissions; integration must add NAMES/art/inventory limits before drops.
## (T067 deep-mine quest sources: ochre_earth 赭土 and vein_quartz 脈石英 were
## integrated — World.NAMES, B6/B7 and B9/B10 finds, glass furnace — and left;
## warm_stone 暖岩片 followed — World.NAMES, B12/B13 finds, table_warmer.gd 共餐桌
## 保溫底座. Nothing is proposed any more.)
const PROPOSED_ITEMS := {}

## Existing uses of mine resources, each verifiable against live tables:
## via=craft → World.CRAFT[product].ingredients has item; via=recipe → World.RECIPES;
## via=build → World.BUILD[product] cost has item; via=process →
## World.INDUSTRY.PROCESS[product].ingredients has item; via=freight → mine_freight.ITEMS;
## via=table_warmer → table_warmer.INSTALL_COST has item and product is its INSTALL_ACTION.
const RESOURCE_USES := [
	{"item":"warm_stone","via":"table_warmer","product":"warmer_install"},
	{"item":"ochre_earth","via":"build","product":"glass_furnace"},
	{"item":"vein_quartz","via":"process","product":"crystal_sand"},
	{"item":"crystal_sand","via":"process","product":"glass"},
	{"item":"stone","via":"craft","product":"kiln_kit"},
	{"item":"stone","via":"craft","product":"mill_kit"},
	{"item":"stone","via":"freight","product":""},
	{"item":"copper_ore","via":"craft","product":"copper_joint"},
	{"item":"copper_ore","via":"freight","product":""},
	{"item":"gold_ore","via":"craft","product":"gold_sample"},
	{"item":"gold_ore","via":"freight","product":""},
	{"item":"crystal_sand","via":"craft","product":"glass"},
	{"item":"star_mushroom","via":"recipe","product":"trout_hotpot"},
]

## Commission performed at the service station of depth `from` to open from+1.
## B5→B6 is new; B1–B4 keep mine_depths.COSTS. Existing item IDs only.
const COMMISSIONS := {
	5:{"title":"加固下行坑道","cost":{"plank":8,"copper_joint":4}},
	6:{"title":"鋪設碎石擋牆","cost":{"stone":16,"charcoal":4}},
	7:{"title":"接通排水管線","cost":{"pipe_kit":2,"tank_kit":1}},
	8:{"title":"安裝玻璃燈罩","cost":{"glass":4,"copper_joint":2}},
	9:{"title":"架設滲水泵站","cost":{"pump_kit":1,"pipe_kit":4}},
	10:{"title":"搭建晶洞棧道","cost":{"plank":12,"resin":4}},
	11:{"title":"鋪設運料輸送帶","cost":{"conveyor_kit":2,"stone":12}},
	12:{"title":"架設暖岩通風管","cost":{"copper_joint":6,"glass":2,"charcoal":4}},
	13:{"title":"窄縫安全繩道","cost":{"plank":10,"fiber":8,"resin":4}},
	14:{"title":"提燈大廳落成","cost":{"gold_sample":2,"copper_joint":6,"plank":10}},
}

## layout_template = index (1..5) into mine_layout.SIDE_CAVES to reuse; survey point
## is mine_survey.POINTS[layout_template]. exits never cost items or energy.
const DEPTHS := {
	6:{"zone":"rust_vein","title":"鏽紋岔道","ore":"copper_ore","yield":4,"finds":["stone","ochre_earth"],"proposed":[],
		"hazard":"drip","layout_template":1,"history":"",
		"exits":{"up":"mine_5","down":"mine_7","lift":SURFACE},
		"survey":{"title":"紅褐色的紋路","text":"岩面一道道紅褐色紋路，像淋過雨的舊鐵欄杆留下的鏽痕。","hint":"第 6 層北側支洞。","icon":"copper_ore"}},
	7:{"zone":"rust_vein","title":"紅土坡道","ore":"stone","yield":6,"finds":["copper_ore","ochre_earth"],"proposed":[],
		"hazard":"loose_gravel","layout_template":2,"history":"",
		"exits":{"up":"mine_6","down":"mine_8","lift":SURFACE},
		"survey":{"title":"坡上的碎石","text":"碎石沿坡面滑落後堆成扇形，記下哪裡適合鋪擋牆。","hint":"第 7 層東側坡道。","icon":"stone"}},
	8:{"zone":"rust_vein","title":"銅綠拱廊","ore":"copper_ore","yield":6,"finds":[],"proposed":[],
		"hazard":"low_ceiling","layout_template":4,"history":"",
		"exits":{"up":"mine_7","down":"mine_9","lift":SURFACE},
		"survey":{"title":"低矮的拱頂","text":"拱頂上的綠色斑點連成一片，提燈靠近時才看得清楚。","hint":"第 8 層北側矮洞。","icon":"copper_joint"}},
	9:{"zone":"seep_geode","title":"滲泉小廳","ore":"stone","yield":4,"finds":["crystal_sand","vein_quartz"],"proposed":[],
		"hazard":"seep","layout_template":3,"history":"",
		"exits":{"up":"mine_8","down":"mine_10","lift":SURFACE},
		"survey":{"title":"岩縫的水聲","text":"水從岩縫滲出，在地上匯成細流，流向南側低處。","hint":"第 9 層南側支洞。","icon":"pipe_kit"}},
	10:{"zone":"seep_geode","title":"晶簾洞","ore":"copper_ore","yield":4,"finds":["crystal_sand","vein_quartz"],"proposed":[],
		"hazard":"mist","layout_template":5,"history":"",
		"exits":{"up":"mine_9","down":"mine_11","lift":SURFACE},
		"survey":{"title":"垂下的晶簾","text":"細小晶體沿岩壁排成一片，水霧裡閃著淡光。","hint":"第 10 層東側深洞。","icon":"crystal_sand"}},
	11:{"zone":"seep_geode","title":"回音水廊","ore":"gold_ore","yield":2,"finds":["crystal_sand"],"proposed":[],
		"hazard":"seep","layout_template":3,"history":"",
		"exits":{"up":"mine_10","down":"mine_12","lift":SURFACE},
		"survey":{"title":"水廊的回音","text":"拍一下手，聲音沿著水廊來回好幾次，記下回音最長的位置。","hint":"第 11 層南側水廊。","icon":"tank_kit"}},
	12:{"zone":"warm_rock","title":"暖岩前廳","ore":"gold_ore","yield":2,"finds":["stone","warm_stone"],"proposed":[],
		"hazard":"warm_air","layout_template":1,"history":"",
		"exits":{"up":"mine_11","down":"mine_13","lift":SURFACE},
		"survey":{"title":"微溫的岩面","text":"手掌貼上岩面，能感到一點溫度。礦務站把這一帶叫作「暖岩」。","hint":"第 12 層北側支洞。","icon":"charcoal"}},
	13:{"zone":"warm_rock","title":"赤脈走廊","ore":"copper_ore","yield":8,"finds":["gold_ore","warm_stone"],"proposed":[],
		"hazard":"warm_air","layout_template":2,"history":"thirteen_levels_name",
		"exits":{"up":"mine_12","down":"mine_14","lift":SURFACE},
		"survey":{"title":"交錯的赤色礦脈","text":"兩道礦脈在走廊轉角交會，一道偏紅，一道偏金。","hint":"第 13 層東側走廊。","icon":"gold_ore"}},
	14:{"zone":"warm_rock","title":"金砂裂谷","ore":"gold_ore","yield":3,"finds":["crystal_sand"],"proposed":[],
		"hazard":"narrow","layout_template":4,"history":"",
		"exits":{"up":"mine_13","down":"mine_15","lift":SURFACE},
		"survey":{"title":"裂谷底的金砂","text":"裂縫底部積著細砂，提燈一照，裡頭夾著幾點暖色。","hint":"第 14 層北側裂縫。","icon":"gold_sample"}},
	15:{"zone":"lantern_hall","title":"提燈大廳","ore":"stone","yield":4,"finds":["gold_ore","crystal_sand"],"proposed":[],
		"hazard":"none","layout_template":5,"history":"jinguashi_mining_overview",
		"exits":{"up":"mine_14","down":"","lift":SURFACE},
		"survey":{"title":"掛滿提燈的洞廳","text":"每位來過的島民都在這裡掛上一盞提燈，洞廳因此一直亮著。","hint":"第 15 層東側大廳。","icon":"plank"}},
}

## Documented regional history (real 金瓜石/水湳洞 area), kept apart from fiction.
## status "needs_source_check": paraphrase from general knowledge, must be verified
## against a cited source before display_ok may become true.
const HISTORY_NOTES := {
	"jinguashi_mining_overview":{"status":"needs_source_check","display_ok":false,
		"text":"現實中的金瓜石一帶自十九世紀末起開採金礦，之後也開採銅礦，於二十世紀後期停採；今日礦區遺址與博物館園區開放參觀。",
		"flag":"需查核年代與經營者後再顯示；遊戲礦場的十五層並非真實坑道。"},
	"thirteen_levels_name":{"status":"needs_source_check","display_ok":false,
		"text":"水湳洞俗稱「十三層」的遺址是沿山坡興建的選煉廠建築，「層」指廠房階層，與礦坑深度無關。",
		"flag":"第十三層刻意不使用「十三層」之名，以免與真實遺址混淆；顯示前需查核。"},
}

## Words that must not appear in fictional depth/zone/survey/hazard text.
const HISTORY_ONLY_TERMS := ["十三層","本山","公司","戰俘","日治","水湳洞"]
const COMBAT_KEYS := ["enemy","enemies","monster","monsters","damage","hp","attack","combat","weapon","boss"]

static func region_id(depth:int) -> String:
	return "mine_%d"%depth

static func region_ids() -> Array:
	var ids:=[]
	for depth in range(FIRST_NEW_DEPTH,MAX_DEPTH+1):ids.append(region_id(depth))
	return ids

static func depth_of(region:String) -> int:
	if not region.begins_with("mine_") or not region.trim_prefix("mine_").is_valid_int():return 0
	var depth:=int(region.trim_prefix("mine_"))
	return depth if depth>=1 and depth<=MAX_DEPTH else 0

static func entry(depth:int) -> Dictionary:
	return DEPTHS.get(depth,{})

static func zone_of(depth:int) -> String:
	if EXISTING.has(depth):return EXISTING[depth].zone
	return entry(depth).get("zone","")

static func commission_from(depth:int) -> Dictionary:
	return COMMISSIONS.get(depth,{})

static func energy_multiplier(depth:int) -> float:
	var hazard:String=entry(depth).get("hazard","none")
	return float(HAZARDS.get(hazard,HAZARDS.none).energy_multiplier)

## Deepest lift landing the surface hoist may use for a given unlocked depth.
static func lift_landing(unlocked:int) -> int:
	var best:=0
	for landing in LIFT_LANDINGS:
		if landing<=unlocked:best=landing
	return best

## INTEGRATION (not done here; touches shared files owned by other workers):
## 1. mine_depths.gd: IDS += region_ids(); ORES/YIELDS += DEPTHS ore/yield;
##    COSTS index 4.. from COMMISSIONS; valid() level cap 5→MAX_DEPTH; keep the
##    pumped invariant for B3 only. Add LIFT to protected tiles.
## 2. mine_layout.gd: side_caves(depth) → SIDE_CAVES[layout_template-1] for depth>5.
## 3. regions.gd ALL += region_ids(); water rule unchanged (POOL stays B3-only).
## 4. world.gd mine_travel: accept LIFT→SURFACE from any depth ≥6 with no cost/energy
##    check; surface hoist lowers to lift_landing(unlocked). Apply
##    energy_multiplier(depth) to mine_energy drain; when energy hits 0, existing
##    rest behaviour applies (no damage). Extend crystal_sand drop beyond B5 using
##    DEPTHS.finds. PROPOSED_ITEMS stay out until NAMES/art/limits exist.
## 5. mine_ui.gd: badges range(1,6)→range(1,MAX_DEPTH+1) (needs a two-row strip at
##    32px), "down" depth<5 → depth<MAX_DEPTH, add "lift" site. Service uses
##    COMMISSIONS[depth].cost for depth≥5.
## 6. mine_survey.gd: POINTS/ENTRIES extend with DEPTHS.survey; seen keys "1".."15";
##    keep the existing five-page reward claim, add a separate deep-survey reward.
## 7. save_schema.gd: migration keeping unlocked≤5 saves valid; bump schema version.
## 8. mine_freight.gd ITEMS unchanged (all DEPTHS ores are already freightable).
## 9. history_ui.gd: show HISTORY_NOTES only after status becomes "verified".
