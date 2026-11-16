extends RefCounted
const ISLAND_NOTES=preload("res://scripts/island_notes.gd")
const DOCK_REPAIRS := [{"plank":12,"stone":8},{"plank":8,"fiber":10,"copper_joint":2}]
const OUTLYING_COMMISSIONS=preload("res://scripts/outlying_commissions.gd")
const ISLAND_STORY_RECAP=preload("res://scripts/island_story_recap.gd")
const BUILD_STYLES = preload("res://scripts/build_style_catalog.gd")
const TRADE = preload("res://scripts/trade_offer.gd")
const TRADE_ACTIONS := ["trade_open", "trade_edit", "trade_confirm", "trade_cancel"]
# Offers are transient. Only the completed inventory swap and its receipt persist.
var trade_offers: Dictionary = {}
## T015 persistent transaction journal (state.ledger, see transaction_ledger.gd).
const TRANSACTION_LEDGER=preload("res://scripts/transaction_ledger.gd")
## Rejected economy requests since the last successful commit. Not saved by a
## rejection itself (a refused request still leaves state untouched); merged into
## state.ledger.rejected by the next committed request's atomic save.
var _ledger_pending: Array = []
const PLOT_PERMISSIONS=preload("res://scripts/plot_permissions.gd")
const MINE_DRILL=preload("res://scripts/mine_drill.gd")
const WATERWORKS=preload("res://scripts/waterworks.gd")
const STATION_LIFE=preload("res://scripts/station_life.gd")
const BOBO_WORKSHOP=preload("res://scripts/bobo_workshop.gd")
const MINE_AUTO_FREIGHT=preload("res://scripts/mine_auto_freight.gd")
const MINE_SURVEY=preload("res://scripts/mine_survey.gd")
const TEA_CERAMICS=preload("res://scripts/tea_ceramics.gd")
const MINE_FREIGHT=preload("res://scripts/mine_freight.gd")
const MINES=preload("res://scripts/mine_depths.gd")
const JINGUASHI=preload("res://scripts/jinguashi.gd")
const HISTORY_MEMORY=preload("res://scripts/history_memory.gd")
const LANYANG_LIFE=preload("res://scripts/lanyang_life.gd")
const TRANSIT=preload("res://scripts/transit.gd")
const REGIONS=preload("res://scripts/regions.gd")
const VILLAGE_LAYOUT=preload("res://scripts/village_layout.gd")
const COMMUNITY=preload("res://scripts/community.gd")
const COIN_CAP_MSG:="鈴幣已達上限，先花掉一些再來。"
const FUND_DONATIONS:=["10","25","50"]
const FUND_MATERIAL_PRICES:={"wood":5,"stone":8}
const ORDER_CATALOG=preload("res://scripts/order_catalog.gd")
const LIVESTOCK=preload("res://scripts/livestock.gd")
const CHAPTER_ONE=preload("res://scripts/chapter_one.gd")
const SHIPPING=preload("res://scripts/shipping.gd")
const Village=preload("res://scripts/village.gd")
const RESIDENT_BOND=preload("res://scripts/resident_bond.gd")
const RESIDENT_GOALS=preload("res://scripts/resident_goals.gd")
const MARKET=preload("res://scripts/market_stall.gd")
const HARVEST=preload("res://scripts/harvest_relay.gd")
const FISH_MEET=preload("res://scripts/fishing_meet.gd")
const SHOWCASE=preload("res://scripts/showcase.gd")
const SOUVENIR=preload("res://scripts/souvenir_exchange.gd")
const TABLE_WARMER=preload("res://scripts/table_warmer.gd")
const LANYANG_REVISIT=preload("res://scripts/lanyang_revisit.gd")
const JINGUASHI_REVISIT=preload("res://scripts/jinguashi_revisit.gd")
const GOLD_PANNING=preload("res://scripts/gold_panning.gd")
const ORE_ROUTE=preload("res://scripts/ore_route.gd")
const TEA_REVISIT=preload("res://scripts/tea_revisit.gd")
const TEA_SERVICE=preload("res://scripts/tea_service.gd")
const SALT_REVISIT=preload("res://scripts/salt_revisit.gd")
const SALT_BRINE=preload("res://scripts/salt_brine.gd")
const MEMORY_EXHIBIT=preload("res://scripts/memory_exhibit.gd")
const Festival=preload("res://scripts/festival.gd")
const LOGISTICS=preload("res://scripts/logistics.gd")
const TILLER=preload("res://scripts/tiller.gd")
const SEEDER=preload("res://scripts/seeder.gd")
const HARVESTER=preload("res://scripts/harvester.gd")
const FORESTRY=preload("res://scripts/forestry.gd")
const INDUSTRY=preload("res://scripts/industry.gd")
const Collections=preload("res://scripts/collections.gd")
const FishingTracking=preload("res://scripts/fishing_tracking.gd")
const AUTO_ROOF_PLAN=preload("res://scripts/auto_roof_plan.gd")
const AUTO_ROOF_SETTLEMENT=preload("res://scripts/auto_roof_settlement.gd")
const CONSTRUCTION_UNDO=preload("res://scripts/construction_undo.gd")
const CONSTRUCTION_HISTORY=preload("res://scripts/construction_history.gd")
const BLUEPRINT_DESIGN=preload("res://scripts/blueprint_design.gd")
const COOKING_QUEUE=preload("res://scripts/cooking_queue.gd")
const MATERIAL_SOURCES=preload("res://scripts/material_sources.gd")
const SAVE_SCHEMA=preload("res://scripts/save_schema.gd")
const PUBLIC_KITCHEN=preload("res://scripts/public_kitchen.gd")
const WEATHER=preload("res://scripts/weather.gd")
const FLOWER_NURSERY=preload("res://scripts/flower_nursery.gd")
const SALT_PAN=preload("res://scripts/salt_pan.gd")
const COOKING_MSG_CORRUPT := "石灶料理資料有誤，這次沒有變更"
const COOKING_MSG_BUSY := "石灶還有排程或待領取的料理，先領取或取消再搬動或拆除"
const PROCESSING_MSG_CORRUPT := "加工排程資料有誤，這次沒有變更"
const PROCESSING_MSG_BUSY := "加工排程還有進行中、等候或待領取的工作，請先領取或取消"
## T067 Q07 「卡住的升降台」: shared hoist repair at the Jinguashi entry sign.
const HOIST_ACTION := "mine_hoist_repair"
const HOIST_STUCK_MSG := "升降台卡住了，先在下坑路牌交付修理材料。"
const HOIST_OK_MSG := "升降台修好了，可以直達已開通的停靠層。波波送來玻璃爐圖樣。"
const HOIST_LOCKED_MSG := "先開通第 6 層，才知道升降台卡在哪裡。"
const HOIST_DONE_MSG := "升降台已經修好了。"
const HOIST_SHORT_MSG := "修理材料不足。"
const GLASS_FURNACE_LOCKED_MSG := "修好金瓜石的升降台後，波波會送來玻璃爐圖樣。"
const UNDO_ACTION := "undo_build"
const UNDO_ACTIONS := ["build","build_area","remove","move_object"]
const UNDO_SOLID := ["ore_display", "wall", "window", "chest", "private_chest", "supply_box", "bench", "bed", "table", "stove","long_bench","sofa","planter","greenhouse_rack","master_flower_bed","fish_display","author_sign","author_shelf","expedition_tent","sprinkler","medium_sprinkler","water_tank","water_tower","water_pump","waterworks","mine_drill","sawmill","charcoal_kiln","forester","mill","seed_maker","loom","glass_furnace"]
## Q05 bakery: the flour mill kit and the mill itself unlock only once the
## shared public kitchen has opened (state.public_kitchen.opened). Every route
## (plain/sourced craft, build, blueprint simulation, undo restore) uses this.
const KITCHEN_GATED := ["mill_kit","mill"]
const MILL_LOCKED_MSG := "麵粉磨坊要等公共廚房開張後才能製作或建造：先在共用餐桌登記公共廚房，再和大家備齊蘿蔔湯 4、麵包 2、菜園沙拉 2。"
## Chapter 3 Tianwei: only nursery-bed care (hoe/seed/water/harvest, remove of
## own empty beds) and the FlowerNursery stations are open there.
## T014 chest stack moves. extra stays the plain item id; the amount is decided
## by the action name from the CURRENT source count (deposit/withdraw keep the
## original single-unit meaning). See chest_move_amount().
const CHEST_MOVES := ["deposit","withdraw","deposit_half","withdraw_half","deposit_all","withdraw_all"]
const FLOWER_REJECTED := ["build","build_area","move_object","plant_tree","axe","pick","till_area","seed_area","harvest_area","deposit","withdraw","deposit_half","withdraw_half","deposit_all","withdraw_all","craft","cook","queue_cook","claim_cook","cancel_cook","cancel_queued_cook","fish_start","fish_catch","door","prepare_material_box"]
const FLOWER_REJECT_MSG := "田尾花圃只開放育苗床照顧和花圃工作台。"
const FLOWER_HOME_SEED_MSG := "完成田尾花圃的第三章後，小栗才會進花卉種子。"
const FLOWER_LOCKED_MSG := "先在鶯歌陶坊完成茶陶比較，再到渡口小栗身旁收下田尾的介紹信。"
## Chapter 4 Beimen salt pans (save 26). Allowed there: movement, transit,
## rescue, every salt_* action, CHEST_MOVES on chests, and build/remove of a
## chest/private_chest ONLY on a private salt lot's chest-socket cell (build by
## the lot holder); undo_build only ever restores those chests. Everything else
## is rejected with SaltPan.REJECT_MESSAGE. The two kits are craft-gated per
## player (SaltPan.craft_allowed) on the plain and the sourced craft path.
const SALT_GATED := ["salt_wheel_kit","salt_rake_kit"]
const PRIVATE_BOXES := ["private_chest","supply_box"]
const SUPPLY_BOX_LEVEL := 6
const EXPEDITION_TENT_LEVEL := 10
const SALT_BOXES := ["chest","private_chest"]
const SALT_HOME_MSG := "請回到渡口，在小栗的攤位旁辦理北門鹽田的信件與委託。"
const SALT_REGION_MSG := "請到北門合作鹽田使用這項功能。"
const SALT_SOCKET_MSG := "只有這塊鹽田區的認領人，可以在收鹽箱位置放箱子。"
const AUTO_ROOF_BUILDS := ["floor","wall","window","door"]
const AUTO_ROOF_AREAS := ["floor"]
const AUTO_ROOF_REMOVES := ["floor","wall","window","door"]

const SIZE := Vector2i(80, 60)
const SPAWN := Vector2(39.5, 33.5)
const TREE_TIME := 180.0
const COPPER_CELL := Vector2i(54,24)
const SPRINKLER_INTERVAL := 8.0
const SPRINKLER_CAPACITY := INDUSTRY.SPRINKLER_CAPACITIES.sprinkler
const SPRINKLER_LIMIT := INDUSTRY.SPRINKLER_LIMIT
const CRAFT := {
	"gold_sample":{"name":"金工收藏樣本","ingredients":{"gold_ore":3},"yield":1},
	"reinforced_pick":{"name":"強化石鎬","ingredients":{"wood":6,"stone":4,"fiber":2},"yield":1},
	"mine_drill_kit":{"name":"礦脈採掘機","ingredients":MINE_DRILL.COST,"yield":1},
	"waterworks_kit":{"name":"水力加工台","ingredients":WATERWORKS.COST,"yield":1},
	"supply_box_kit":{"name":"便攜補給箱","ingredients":{"plank":4,"fiber":2},"yield":1},
	"glass":{"name":"溫室玻璃","ingredients":{"crystal_sand":2,"charcoal":1},"yield":2},
	"copper_joint":{"name":"銅接頭","ingredients":{"copper_ore":2,"wood":1},"yield":1},
	"sprinkler_kit":{"name":"小型灑水器","ingredients":{"copper_joint":2,"wood":8,"stone":4},"yield":1},
	"pipe_kit":{"name":"銅水管","ingredients":{"copper_joint":1,"resin":1},"yield":2},
	"tank_kit":{"name":"儲水桶","ingredients":{"plank":4,"resin":2},"yield":1},
	"pump_kit":{"name":"河水泵","ingredients":{"copper_joint":2,"plank":2,"charcoal":2},"yield":1},
	"sawmill_kit":{"name":"鋸木台","ingredients":{"wood":8,"stone":4},"yield":1},
	"kiln_kit":{"name":"炭窯","ingredients":{"stone":8,"wood":4},"yield":1},
	"forester_kit":{"name":"林務工作站","ingredients":{"plank":8,"copper_joint":4,"resin":4,"stone":8,"charcoal":4},"yield":1},
	"conveyor_kit":{"name":"輸送帶","ingredients":{"plank":2,"copper_joint":1,"resin":1},"yield":2},
	"tiller":{"name":"手推耕田機","ingredients":{"plank":12,"copper_joint":8,"stone":16,"charcoal":6,"resin":4},"yield":1},
	"seeder":{"name":"手推播種機","ingredients":{"plank":10,"copper_joint":10,"fiber":12,"resin":6,"charcoal":4},"yield":1},
	"harvester":{"name":"手推收割機","ingredients":{"plank":16,"copper_joint":12,"stone":20,"fiber":8,"resin":6,"charcoal":6},"yield":1},
	"mill_kit":{"name":"麵粉磨坊","ingredients":{"plank":8,"stone":16,"copper_joint":4},"yield":1},
	# Chapter 4 salt machines (= SaltPan.CRAFT; gated by SaltPan.craft_allowed).
	"salt_wheel_kit":{"name":"鹽田水車組","ingredients":{"plank":8,"copper_joint":2,"resin":2},"yield":1},
	"salt_rake_kit":{"name":"收鹽台組","ingredients":{"plank":6,"stone":6,"fiber":4,"copper_joint":1},"yield":1},
	# Chapter 40 分流閘 (= INDUSTRY.GATE_KIT): craftable only after the Lanyang revisit
	# (LANYANG_REVISIT.tech_unlocked) on the plain and the sourced craft path.
	"diversion_gate_kit":{"name":"分流閘","ingredients":{"plank":2,"copper_joint":1,"stone":2},"yield":1},
	# Chapter 40 水塔 (= INDUSTRY.TOWER_KIT): same Lanyang-revisit lock as the gate kit
	# (INDUSTRY.TOWER_LOCKED) on the plain and the sourced craft path.
	"water_tower_kit":{"name":"水塔","ingredients":{"plank":6,"copper_joint":2,"stone":6},"yield":1},
}
# One point per harvested plot, including each successful repeat harvest.
const EXPLORATION_LEVEL_THRESHOLDS := [0,1,2,4,6,8,10,11,12,14]
const BATCH_BUILD_LEVEL := 6
const BASIC_BUILD_AREA := 25
const CRAFTING_LEVEL_THRESHOLDS := [0,4,10,20,35,55,80,110,145,185]
const GATHERING_LEVEL_THRESHOLDS := [0,4,10,20,35,55,80,110,145,185]
const SAPLING_RECOVERY_LEVEL := 3
const RESOURCE_MAP_LEVEL := 6
const FARMING_LEVEL_THRESHOLDS := [0,4,10,20,35,55,80,110,145,185]
const SEED_MAKER_LEVEL := 3
const MEDIUM_SPRINKLER_LEVEL := 6
const MASTER_FARMING_LEVEL := 10
const SEED_MAKER := preload("res://scripts/seed_maker.gd")
const CROPS := preload("res://scripts/crop_catalog.gd").CROPS
const CROP_SEASONS := {
	"radish": ["spring", "autumn"],
	"lettuce": ["spring", "summer"],
	"wheat": ["spring", "summer", "autumn"],
	"carrot": ["spring", "autumn"],
	"potato": ["spring", "winter"],
	"tomato": ["summer"],
	"pumpkin": ["autumn"],
	"cauliflower": ["spring", "winter"],
	"sweet_corn": ["summer", "autumn"],
	"strawberry": ["spring"],
	"cucumber": ["summer"],
	"cabbage": ["winter"],
	"sugar_beet": ["winter"],
	"sweet_potato": ["autumn"],
	"eggplant": ["summer", "autumn"],
	"rice": ["summer", "autumn"],
	"watermelon": ["summer"],
	"ginger": ["winter"],
	"cotton": ["spring", "summer"],
	"bluebell": ["spring"],
	"orange_blossom": ["summer", "autumn"],
}
const BUILD := {
	"loom":{"name":"織布機","plank":8,"fiber":4,"copper_joint":1},
	# T067 Q07 reward: blueprint unlocked by repairing the Jinguashi hoist.
	"glass_furnace":{"name":"玻璃爐","stone":12,"ochre_earth":4,"copper_joint":2},
	"seed_maker":{"name":"種子機","plank":8,"stone":6,"copper_joint":2},
	"ore_display":{"name":"礦樣展示架","wood":4,"gold_sample":1},
	"floor": {"name": "木地板", "wood": 2},
	"wall": {"name": "木牆", "wood": 3},
	"path": {"name": "石板路", "stone": 2},
	"chest": {"name": "共用箱", "wood": 20},
	"bench": {"name": "工作台", "wood": 20, "stone": 5},
	"bed": {"name": "小床", "wood": 15, "fiber": 10},
	"lamp": {"name": "木燈", "wood": 5, "stone": 2},
	"door": {"name": "木門", "wood": 6, "fiber": 2},
	"window": {"name": "採光木牆", "wood": 6, "stone": 1},
	"greenhouse_roof":{"name":"溫室玻璃棚","glass":2,"copper_joint":1},
	"roof": {"name": "草編屋頂", "wood": 1, "fiber": 3},
	"table": {"name": "小木桌", "wood": 12},
	"chair": {"name": "木椅", "wood": 6},
	"stove": {"name": "小石灶", "wood": 12, "stone": 15},
	"supply_box":{"name":"便攜補給箱","supply_box_kit":1},
	"private_chest": {"name": "私人箱", "wood": 20},
	"long_bench":{"name":"雙人長椅","wood":14,"fiber":4},
	"author_sign":{"name":"工匠署名牌","plank":3,"fiber":1},
	"expedition_tent":{"name":"探險紀念帳篷","plank":6,"wool_cloth":2},
	"author_shelf":{"name":"工匠展示架","plank":6,"glass":1},
	"fish_display":{"name":"島岸魚譜展示櫃","glass":2,"plank":6},
	"master_flower_bed":{"name":"豐收花圃","plank":4,"stone":2,"fiber":2},
	"greenhouse_rack":{"name":"溫室花架","plank":4,"fiber":2},
	"planter":{"name":"窗邊花箱","wood":8,"stone":3},
	"sign":{"name":"手刻歡迎牌","wood":5},
	"sofa":{"name":"棉布小沙發","wood":18,"cotton_cloth":2},
	"sprinkler":{"name":"小型灑水器","sprinkler_kit":1},
	"medium_sprinkler":{"name":"中型灑水器","sprinkler_kit":1,"copper_joint":3,"plank":4},
	"water_pipe":{"name":"銅水管","pipe_kit":1},
	"water_tank":{"name":"儲水桶","tank_kit":1},
	"mine_drill":{"name":"礦脈採掘機","mine_drill_kit":1},
	"waterworks":{"name":"水力加工台","waterworks_kit":1},
	"water_pump":{"name":"河水泵","pump_kit":1},
	"sawmill":{"name":"鋸木台","sawmill_kit":1},
	"charcoal_kiln":{"name":"炭窯","kiln_kit":1},
	"forester":{"name":"林務工作站","forester_kit":1},
	"conveyor":{"name":"輸送帶","conveyor_kit":1},
	"mill":{"name":"麵粉磨坊","mill_kit":1},
	# T071 紀念票兌換裝飾（= SOUVENIR.ENTRIES）：只能用紀念品交換攤換到的 kit 擺放，
	# 拆除退回 kit；不擋路（不在 UNDO_SOLID）。
	"veg_basket_rack":{"name":"菜籃小架","veg_basket_rack_kit":1},
	"relay_crate_stack":{"name":"接力菜箱堆","relay_crate_stack_kit":1},
	"carp_banner":{"name":"鯽魚布旗","carp_banner_kit":1},
	"float_garland":{"name":"浮球串飾","float_garland_kit":1},
	"lantern_post":{"name":"紙燈籠柱","lantern_post_kit":1},
	"flower_arch":{"name":"花草拱架","flower_arch_kit":1},
	"trio_keepsake":{"name":"三活動紀念牌","trio_keepsake_kit":1},
	# T066「一起做的事」第三批紀念小物（= RESIDENT_GOALS.KEEPSAKES）：完成該項行動時得到
	# kit；不擋路、拆除退回 kit、沒有價目、不能交易。只是裝飾。
	"keepsake_aru":{"name":"有點歪的第一塊板","keepsake_aru_kit":1},
	"keepsake_milu":{"name":"試吃會的空碗","keepsake_milu_kit":1},
	"keepsake_bobo":{"name":"排成小島的石頭","keepsake_bobo_kit":1},
	"keepsake_chacha":{"name":"換下來的舊竹片","keepsake_chacha_kit":1},
	"keepsake_achao":{"name":"鬆開的舊繩結","keepsake_achao_kit":1},
	"keepsake_mianmian":{"name":"縫線有點歪的玩具","keepsake_mianmian_kit":1},
	"keepsake_xinghe":{"name":"留了一格空白的花圃圖紙","keepsake_xinghe_kit":1},
	"keepsake_lingpopo":{"name":"留著你的顏色的鈴","keepsake_lingpopo_kit":1},
	"keepsake_xiaoli":{"name":"招牌的試寫木片","keepsake_xiaoli_kit":1},
	"keepsake_luoluo":{"name":"寫給以後的信封","keepsake_luoluo_kit":1},
	"keepsake_diandian":{"name":"畫著放鬆的手的速寫","keepsake_diandian_kit":1},
	"keepsake_nuannuan":{"name":"亮起來的門牌","keepsake_nuannuan_kit":1},
	# Chapter 40: 蘭陽回訪 memento (LANYANG_REVISIT.PLAQUE_*): same rules as the T071
	# decor kits (walk-through, removal returns the kit, no price, no trade).
	"water_share_plaque":{"name":"分水木牌","water_share_plaque_kit":1},
	# Chapter 40: 金瓜石回訪 memento (JINGUASHI_REVISIT.LANTERN_*): same rules as the
	# water-share plaque (walk-through, removal returns the kit, no price, no trade).
	# Decoration only: no lighting mechanic.
	"mine_lantern":{"name":"礦燈","mine_lantern_kit":1},
	# Chapter 40: 貓空與鶯歌回訪 memento (TEA_REVISIT.TEAWARE_*): same rules as the mine
	# lantern (walk-through, removal returns the kit, no price, no trade). Decoration only:
	# no serving mechanic.
	"tea_ware":{"name":"茶陶組","tea_ware_kit":1},
	# Chapter 40: 臺南北門回訪 memento (SALT_REVISIT.BASKET_*): same rules as the tea ware
	# (walk-through, removal returns the kit, no price, no trade). Decoration only.
	"salt_basket":{"name":"鹽籃","salt_basket_kit":1},
	# Chapter 40 home diversion gate (INDUSTRY.GATE_*): a walk-through network piece
	# like water_pipe; field `mode` open/low/closed (gate_mode action).
	"diversion_gate":{"name":"分流閘","diversion_gate_kit":1},
	# Chapter 40 home water tower (INDUSTRY.TOWER_*): a solid network piece like
	# water_tank; fields `water` 0..TOWER_CAPACITY and `enabled` (tower_toggle action).
	"water_tower":{"name":"水塔","water_tower_kit":1},
}
const FISH := Collections.FISH
const RECIPES := {"soup":{"name":"熱蘿蔔湯","ingredients":{"radish":2},"time":10.0,"yield":2}, "bread":{"name":"小麥麵包","ingredients":{"wheat":2},"time":15.0,"yield":1}, "feed":{"name":"混合飼料","ingredients":{"wheat":1,"fiber":2},"time":5.0,"yield":4},"salad":{"name":"菜園沙拉","ingredients":{"lettuce":1,"tomato":1},"time":10.0,"yield":2},"baked_potato":{"name":"烤馬鈴薯","ingredients":{"potato":2},"time":15.0,"yield":2},"grilled_fish":{"name":"香煎鯽魚","ingredients":{"carp":1},"time":10.0,"yield":1},"carrot_soup":{"name":"胡蘿蔔濃湯","ingredients":{"carrot":2},"time":15.0,"yield":2},"pumpkin_pie":{"name":"南瓜派","ingredients":{"pumpkin":1,"flour":1,"egg":1},"time":120.0,"yield":4},
	# garden_cookie (= FlowerNursery.COOKIE): 設計選擇，非原規劃精確配方. Plan §14 only
	# gives the ingredient direction; quantities and 60 s are approved design values.
	"garden_cookie":{"name":"花園餅乾","ingredients":{"flour":1,"sugar":1,"chime_herb":1},"time":60.0,"yield":4},
	# salt_grilled_fish (= SaltPan.RECIPE) 香煎溪魚: minnow 1 + sea_salt 1, 15 s, yield 1.
	"salt_grilled_fish":{"name":"香煎溪魚","ingredients":{"minnow":1,"sea_salt":1},"time":15.0,"yield":1},
	"strawberry_jam":{"name":"草莓果醬","ingredients":{"strawberry":2,"sugar":1},"time":45.0,"yield":2},
	"cucumber_salad":{"name":"涼拌黃瓜","ingredients":{"cucumber":2},"time":12.0,"yield":2},
	"sugar":{"name":"熬製甜菜糖","ingredients":{"sugar_beet":1},"time":40.0,"yield":2},
	"trout_hotpot":{"name":"雪點鱒魚火鍋","ingredients":{"snow_trout":1,"cabbage":1,"star_mushroom":1},"time":60.0,"yield":4},
	"roasted_sweet_potato":{"name":"烤地瓜","ingredients":{"sweet_potato":2},"time":18.0,"yield":2},
	"eggplant_rice":{"name":"茄子燴飯","ingredients":{"rice":2,"eggplant":1},"time":30.0,"yield":2},
	"mist_tea_brew":{"name":"霧竹茶飲","ingredients":{"mist_tea":2},"time":20.0,"yield":2},
	"watermelon_platter":{"name":"夏日西瓜盤","ingredients":{"watermelon":1},"time":8.0,"yield":4},
	# corn_chowder 玉米濃湯（規劃書第 14 章「玉米、牛奶・團隊分享餐」；數量、30 秒、四份與
	# 售價 30 是設計值，規劃書沒有給）。共餐桌的第三道分享餐（community.gd DISHES）。
	"corn_chowder":{"name":"玉米濃湯","ingredients":{"sweet_corn":2,"milk":1},"time":30.0,"yield":4}}
const OTHER_SALES := {"corn_chowder":30,"egg":30,"soup":32,"bread":48,"salad":36,"baked_potato":36,"grilled_fish":26,"carrot_soup":50,"pumpkin_pie":80,"garden_cookie":36,"salt_grilled_fish":34,"strawberry_jam":49,"cucumber_salad":26,"trout_hotpot":60,"roasted_sweet_potato":41,"eggplant_rice":51,"mist_tea_brew":44,"watermelon_platter":38}
## Flower seeds, blue_dye and sugar are deliberately absent from CROPS prices and
## OTHER_SALES: they can never be sold or shipped (no seed-saving arbitrage).
## sea_salt is likewise never sellable, shippable or buyable (no automation pump).
const NAMES := {"corn_chowder":"玉米濃湯","supply_box_kit":"便攜補給箱","moon_squid":"月光小魷","gold_shrimp":"金邊蝦","sardine":"藍背沙丁","flounder":"奶油比目魚","crystal_sand":"晶砂","ochre_earth":"赭土","vein_quartz":"脈石英","warm_stone":"暖岩片","glass":"溫室玻璃","tea_leaf":"新鮮茶葉","clay":"陶土","tea_jar":"陶罐","tea_returned_jar":"回收陶罐","tea_worn_jar":"磨損陶罐","tea_spent_jar":"待修陶罐","tea_light":"淺焙茶","tea_deep":"深焙茶","mine_drill_kit":"礦脈採掘機","waterworks_kit":"水力加工台","gold_ore":"含金礦料","gold_sample":"金工收藏樣本","wood":"木材", "stone":"石材", "fiber":"纖維", "radish":"蘿蔔", "lettuce":"萵苣", "wheat":"小麥", "radish_seed":"蘿蔔種子", "lettuce_seed":"萵苣種子", "wheat_seed":"小麥種子", "carp":"圓肚鯽魚", "minnow":"銀線溪魚", "redfish":"紅尾小鯉", "loach":"斑點泥鰍", "egg":"雞蛋", "feed":"飼料", "soup":"蘿蔔湯", "bread":"麵包", "sapling":"小樹苗","carrot":"胡蘿蔔","potato":"馬鈴薯","tomato":"番茄","carrot_seed":"胡蘿蔔種子","potato_seed":"馬鈴薯種子","tomato_seed":"番茄種子","salad":"菜園沙拉","baked_potato":"烤馬鈴薯","grilled_fish":"香煎鯽魚","carrot_soup":"胡蘿蔔濃湯","reinforced_pick":"強化石鎬","copper_ore":"銅礦","copper_joint":"銅接頭","sprinkler_kit":"小型灑水器","plank":"木板","resin":"樹脂","charcoal":"木炭","pipe_kit":"銅水管","tank_kit":"儲水桶","pump_kit":"河水泵","sawmill_kit":"鋸木台","kiln_kit":"炭窯","forester_kit":"林務工作站","conveyor_kit":"輸送帶","tiller":"手推耕田機","seeder":"手推播種機","harvester":"手推收割機","pumpkin":"南瓜","pumpkin_seed":"南瓜種子","flour":"麵粉","pumpkin_pie":"南瓜派","mill_kit":"麵粉磨坊","bluebell":"鈴蘭藍花","orange_blossom":"蜜橙花","chime_herb":"風鈴香草","bluebell_seed":"鈴蘭藍花種子","orange_blossom_seed":"蜜橙花種子","chime_herb_seed":"風鈴香草種子","blue_dye":"藍色染料","sugar":"糖","garden_cookie":"花園餅乾","sea_salt":"海鹽","salt_wheel_kit":"鹽田水車組","salt_rake_kit":"收鹽台組","salt_grilled_fish":"香煎溪魚","cauliflower":"花椰菜","cauliflower_seed":"花椰菜種子","sweet_corn":"甜玉米","sweet_corn_seed":"甜玉米種子","star_spot":"星斑魚","bamboo_ayu":"竹影香魚","glass_shrimp":"玻璃小蝦","snow_trout":"雪點鱒魚","strawberry":"草莓","strawberry_seed":"草莓種子","cucumber":"黃瓜","cucumber_seed":"黃瓜種子","strawberry_jam":"草莓果醬","cucumber_salad":"涼拌黃瓜","cabbage":"高麗菜","cabbage_seed":"高麗菜種子","sugar_beet":"甜菜","sugar_beet_seed":"甜菜種子","star_mushroom":"星夜菇","star_mushroom_seed":"星夜菇菌種","trout_hotpot":"雪點鱒魚火鍋","sweet_potato":"地瓜","sweet_potato_seed":"地瓜種子","eggplant":"茄子","eggplant_seed":"茄子種子","rice":"稻米","rice_seed":"稻種","roasted_sweet_potato":"烤地瓜","eggplant_rice":"茄子燴飯","watermelon":"西瓜","watermelon_seed":"西瓜種子","ginger":"暖泉薑","ginger_seed":"薑種","cotton":"棉球花","cotton_seed":"棉球花種子","mist_tea":"霧竹茶","mist_tea_seed":"霧竹茶種","mist_tea_brew":"霧竹茶飲","watermelon_platter":"夏日西瓜盤","milk":"鮮奶","wool":"羊毛","cotton_cloth":"布料","wool_cloth":"羊毛布","veg_basket_rack_kit":"菜籃小架","relay_crate_stack_kit":"接力菜箱堆","carp_banner_kit":"鯽魚布旗","float_garland_kit":"浮球串飾","lantern_post_kit":"紙燈籠柱","flower_arch_kit":"花草拱架","trio_keepsake_kit":"三活動紀念牌","water_share_plaque_kit":"分水木牌","diversion_gate_kit":"分流閘","water_tower_kit":"水塔","mine_lantern_kit":"礦燈","tea_ware_kit":"茶陶組","salt_basket_kit":"鹽籃","keepsake_aru_kit":"有點歪的第一塊板","keepsake_milu_kit":"試吃會的空碗","keepsake_bobo_kit":"排成小島的石頭","keepsake_chacha_kit":"換下來的舊竹片","keepsake_achao_kit":"鬆開的舊繩結","keepsake_mianmian_kit":"縫線有點歪的玩具","keepsake_xinghe_kit":"留了一格空白的花圃圖紙","keepsake_lingpopo_kit":"留著你的顏色的鈴","keepsake_xiaoli_kit":"招牌的試寫木片","keepsake_luoluo_kit":"寫給以後的信封","keepsake_diandian_kit":"畫著放鬆的手的速寫","keepsake_nuannuan_kit":"亮起來的門牌"}
## T071 紀念票兌換品（*_kit，= SOUVENIR.items()）刻意不在 CROPS／FISH／OTHER_SALES：
## 不能出貨、不能在攤位出售或上市集；trade_items() 也排除，不能和其他玩家交易。
var state: Dictionary
var save_path := ""
var save_error := ""
var recovered_from_backup := false
var rejected_path := ""
## Why the last step() returned false: "" (ok/paused), STEP_FAIL_SALT or
## STEP_FAIL_SAVE. Either failure rolled the whole tick back (no save).
var step_error := ""
const STEP_FAIL_SALT := "salt_step_rejected"
const STEP_FAIL_SAVE := "save_failed"
var active_tokens:Dictionary={}
var _region := REGIONS.HOME
## T034 undo clocks. Empty Callables use Time; tests may inject replacements.
## undo_clock_utc() -> float epoch seconds; undo_clock_ticks() -> int msec.
var undo_clock_utc: Callable
var undo_clock_ticks: Callable
## Same-process monotonic capture ticks per record id (not persisted).
var _undo_ticks_at: Dictionary = {}
## Explicit dependency uses collected during step_region: {region: {tile: true}}.
var _undo_used: Dictionary = {}

func _init() -> void:
	state = {"version":SAVE_SCHEMA.VERSION,"regions":{}, "time":0.0, "players":{}, "crops":{}, "objects":{}, "ground":{}, "roofs":{}, "removed":{}, "damage":{}, "board":false, "donations":{"wood":0,"stone":0}, "events":[], "committed":0, "construction":CONSTRUCTION_HISTORY.fresh()}
	for region in REGIONS.ALL:
		if region!=REGIONS.HOME:state.regions[region]=REGIONS.fresh()
	ensure_life_fields()

func ensure_life_fields() -> void:
	if not state.has("station_life"):state.station_life=STATION_LIFE.fresh()
	if not state.has("bobo_workshop"):state.bobo_workshop=BOBO_WORKSHOP.fresh()
	if not state.has("mine_auto_freight"):state.mine_auto_freight=MINE_AUTO_FREIGHT.fresh()
	if not state.has("mine_survey"):state.mine_survey=MINE_SURVEY.fresh()
	if not state.has("tea_ceramics"):state.tea_ceramics=TEA_CERAMICS.fresh()
	if not state.has("mine_freight"):state.mine_freight=MINE_FREIGHT.fresh()
	if not state.has("mine_depths"):state.mine_depths=MINES.fresh()
	if not state.has("jinguashi"):state.jinguashi={"ready":{}}
	if not state.has("history_memory"):state.history_memory=HISTORY_MEMORY.fresh()
	if not state.has("lanyang_life"):state.lanyang_life=LANYANG_LIFE.fresh()
	if not state.has("festival"):state.festival=Festival.fresh()
	if not state.has("quarry"):state.quarry={"hits":0,"ready":0.0}
	if not state.has("copper"):state.copper={"ready":0.0}
	if not state.has("next_logistics_check"):state.next_logistics_check=0.0
	if not state.has("next_network_check"):state.next_network_check=0.0
	if not state.has("forest"):state.forest={}
	if not state.has("animal"):state.animal={"bond":0,"egg_ready":-1.0,"last_pet":-30.0}
	if not state.has("livestock"):state.livestock={}
	if not state.has("chapter_one"):state.chapter_one=CHAPTER_ONE.fresh()
	if not state.has("picnic"):state.picnic=false
	if not state.has("picnic_materials"):state.picnic_materials={"soup":0,"bread":0}
	if not state.has("construction"):state.construction=CONSTRUCTION_HISTORY.fresh()
	if not state.has("public_kitchen"):state.public_kitchen=PUBLIC_KITCHEN.fresh()
	if not state.has("flower_nursery"):state.flower_nursery=FLOWER_NURSERY.fresh()
	if not state.has("salt_pan"):state.salt_pan=SALT_PAN.fresh()

## Q05: true once the shared public kitchen opened (root field, so the answer
## is identical in every region projection and blueprint simulation copy).
func kitchen_opened() -> bool:
	return PUBLIC_KITCHEN.stage(state)=="open"

static func key(p: Vector2i) -> String:
	return "%d,%d" % [p.x, p.y]

static func cell(k: String) -> Vector2i:
	var a := k.split(",")
	return Vector2i(int(a[0]), int(a[1]))

static func land(p: Vector2i, region: String = REGIONS.HOME) -> bool:
	if region != REGIONS.HOME:return REGIONS.land(p,region)
	var d := Vector2((p.x-39.5)/36.0, (p.y-29.5)/26.0)
	return p.x >= 0 and p.y >= 0 and p.x < SIZE.x and p.y < SIZE.y and d.length_squared() < 1.0 + sin(p.y*0.7)*0.035

static func base_resource(p: Vector2i, region: String = REGIONS.HOME) -> String:
	if region != REGIONS.HOME:return REGIONS.resource(p,region)
	# Keep the illustrated village paths walkable and visually clear. Existing
	# player-planted trees remain in the saved forest layer and are unaffected.
	if VILLAGE_LAYOUT.path_at(Vector2(p)+Vector2(0.5,0.5)):return ""
	if (p.x>=46 and p.x<=51 and p.y>=22 and p.y<=29) or p in [Vector2i(38,29),Vector2i(54,25),COPPER_CELL]:return ""
	if not land(p) or (p.x >= 35 and p.x <= 45 and p.y >= 27 and p.y <= 37): return ""
	if p.x == 55 or p.x == 56: return ""
	var h: int = absi(p.x*7127 + p.y*19391 + p.x*p.y*193)
	if h % 17 == 0: return "tree"
	if h % 23 == 0: return "rock"
	if h % 31 == 0: return "grass"
	return ""

func resource(p: Vector2i) -> String:
	var planted:Dictionary=state.forest.get(key(p),{})
	if not planted.is_empty():return "tree" if planted.mature else "sapling"
	return "" if state.removed.has(key(p)) else base_resource(p,_region)

func is_land(p: Vector2i) -> bool:
	return land(p,_region)

func water(p: Vector2i) -> bool:
	if _region != REGIONS.HOME:return REGIONS.water(p,_region)
	if not land(p): return true
	return (p.x == 55 or p.x == 56) and not (state.board and p.y >= 29 and p.y <= 31)

func bobo_sites() -> Dictionary:
	return BOBO_WORKSHOP.sites(state)

func protected(p: Vector2i) -> bool:
	if _region == REGIONS.JINGUASHI and p in bobo_sites().values():return true
	if _region != REGIONS.HOME:return REGIONS.protected(p,_region)
	# T042: donated public-kitchen stove/seats are permanently public (HOME only).
	if PUBLIC_KITCHEN.is_site_cell(state,p):return true
	if p in [REGIONS.exit_cell(REGIONS.HOME),Vector2i(REGIONS.spawn(REGIONS.HOME))]:
		var tile := key(p)
		for layer in ["objects","ground","roofs","crops","forest"]:
			if state[layer].has(tile):return false
		return true
	if p in [Vector2i(38,29),Vector2i(44,31),Vector2i(54,25)]:return true
	if p in MARKET.CANDIDATES and p==MARKET.active_cell(state):return true # T071 市集攤位（解鎖後保留）
	if HARVEST.reserved(state,p):return true # T071 豐收接力場地（解鎖後空著的格子保留）
	if FISH_MEET.reserved(state,p):return true # T071 河岸釣魚會告示牌（解鎖後空著時保留）
	if SHOWCASE.reserved(state,p):return true # T071 家園布置題告示牌與展示地塊（解鎖後空著的格子保留）
	if SOUVENIR.reserved(state,p):return true # T071 紀念品交換攤（解鎖後使用中的那一格保留）
	if MEMORY_EXHIBIT.reserved(state,p):return true # 第 40 章地方記憶展展台（風鈴節開幕後使用中的那一格）
	return (p.x >= 38 and p.x <= 44 and p.y >= 28 and p.y <= 31) or (p.x >= 54 and p.x <= 57) or (p.x==39 and p.y in [32,33]) or p==Vector2i(45,34)

func blocked(p: Vector2i) -> bool:
	if _region in TRANSIT.TEA_STOPS and REGIONS.tea_blocked(p,_region):return true
	if _region in TRANSIT.LOCAL and (not is_land(p) or TRANSIT.blocked(p,_region)):return true
	if _region == FLOWER_NURSERY.REGION and (not is_land(p) or FLOWER_NURSERY.blocked(p)):return true
	if _region == SALT_PAN.REGION and (not is_land(p) or SALT_PAN.blocked(p)):return true
	if water(p): return true
	if _region in MINES.IDS and p in MINES.NODES:return true
	if _region == REGIONS.JINGUASHI and (p in JINGUASHI.NODES or JINGUASHI.ENTRANCE_FOOTPRINT.has_point(p)):return true
	if _region == REGIONS.JINGUASHI and p == bobo_sites().table:return true
	if _region == REGIONS.HOME:
		if state.get("festival_story_open",false) and p in Village.FESTIVAL_SPOTS.values():return true
		if (p in COMMUNITY.CANDIDATES and p == COMMUNITY.table_cell(state)) or p==COPPER_CELL or (p in SHIPPING.CANDIDATES and p == SHIPPING.cell_for(state)):return true
		if p in MARKET.CANDIDATES and p == MARKET.active_cell(state):return true
		if HARVEST.reserved(state,p):return true
		if FISH_MEET.reserved(state,p):return true
		if SHOWCASE.blocks(state,p):return true # 只有告示牌擋路，展示地塊照樣能走
		if SOUVENIR.blocks(state,p):return true # T071 紀念品交換攤擋路
		if MEMORY_EXHIBIT.blocks(state,p):return true # 第 40 章地方記憶展展台擋路
		if p == Vector2i(40,29) or p == Vector2i(43,29): return true
		if p in [Vector2i(38,29),Vector2i(44,31),Vector2i(54,25)]:return true
	var r := resource(p)
	if r == "tree" or r == "rock": return true
	var o: Dictionary = state.objects.get(key(p), {})
	if o.get("type","")=="door":return not o.get("open",false)
	return o.get("type", "") in UNDO_SOLID

func add_player(token: String, name: String) -> void:
	active_tokens[token]=true
	if not state.players.has(token):
		state.players[token] = {"name":name.left(12), "region":REGIONS.HOME, "travel_epoch":0, "travel_book":TRANSIT.fresh(), "mine_energy":100, "x":SPAWN.x, "y":SPAWN.y, "coins":120, "inventory":{"wood":12,"stone":4,"fiber":10,"radish_seed":5,"lettuce_seed":3,"wheat_seed":3,"sapling":2}, "receipts":{}, "harvests":0, "builds":0}
	else: state.players[token].name = name.left(12)
	Village.ensure_player(state.players[token])
	Collections.ensure_player(state.players[token])
	if not state.players[token].has("crafted_reinforced_pick"):state.players[token].crafted_reinforced_pick=false
	var current := player_region(token)
	switch_region(current)
	var person: Dictionary = state.players[token]
	if not can_stand(Vector2(person.x,person.y)):
		var point := safe_arrival(REGIONS.spawn(current) if current != REGIONS.HOME else SPAWN)
		if point != Vector2.ZERO:
			person.x = point.x
			person.y = point.y
	switch_region(REGIONS.HOME)

func safe_arrival(preferred: Vector2) -> Vector2:
	if can_stand(preferred):return preferred
	for radius in range(1,5):
		for y in range(-radius,radius+1):
			for x in range(-radius,radius+1):
				var candidate := preferred + Vector2(x,y)
				if can_stand(candidate):return candidate
	return Vector2.ZERO

func player_region(token: String) -> String:
	return state.players.get(token, {}).get("region", REGIONS.HOME)

func own_crop_summary(token:String) -> Dictionary:
	var summary:={ "ready":0, "growing":0, "dry":0 }
	for region:String in REGIONS.ALL:
		var layers:Dictionary=_layers_of(region)
		for plot:Dictionary in layers.get("crops",{}).values():
			var kind:=str(plot.get("kind",""))
			if plot.get("owner")!=token or not CROPS.has(kind):continue
			if float(plot.get("growth",0))>=float(CROPS[kind].time):summary.ready+=1
			else:
				summary.growing+=1
				if not plot.get("wet",false):summary.dry+=1
	return summary

func island_project_mask() -> int:
	return (int(state.get("board",false))
		| (int(state.get("lanyang_life",{}).get("repaired",false))<<1)
		| (int(state.get("flower_nursery",{}).get("garden",{}).get("complete",false))<<2)
		| (int(SALT_PAN.repaired(state))<<3)
		| (int(state.get("public_kitchen",{}).get("opened",false))<<4)
		| (int(int(state.get("mine_depths",{}).get("unlocked",1))>=5)<<5))

func festival_story_view() -> Dictionary:
	var table:=COMMUNITY.table_cell(state)
	var lights:=0
	if table!=COMMUNITY.NO_CELL:
		var objects:Dictionary=home_layer("objects")
		for y in range(table.y-3,table.y+4):
			for x in range(table.x-3,table.x+4):
				if objects.get(key(Vector2i(x,y)),{}).get("type")=="lamp":lights+=1
	return {"projects":island_project_mask(),"lights":lights,
		"boat_ready":TRANSIT.boat_open(state),
		"meal":COMMUNITY.DISHES.keys().any(func(dish):return int(state.get("community",{}).get(dish,{}).get("portions",0))>0),
		"opened":bool(state.get("festival_story_open",false))}

func region_snapshot(region: String) -> Dictionary:
	if region not in REGIONS.ALL:return {}
	var result := state.duplicate(true)
	if region != REGIONS.HOME:
		for field in REGIONS.LAYERS:result[field] = result.regions[region][field]
	result.erase("regions")
	# Server-only undo history (raw tokens, record ids, inventory deltas).
	result.erase("construction")
	# T015 server-only transaction journal; players read it via ledger_view only.
	result.erase(TRANSACTION_LEDGER.STATE_KEY)
	result.region_id = region
	for token in result.players.keys():
		if player_region(token) != region:result.players.erase(token)
	return result

func switch_region(region: String) -> void:
	if region == _region:return
	if _region != REGIONS.HOME:swap_region_layers(_region)
	if region != REGIONS.HOME:swap_region_layers(region)
	_region = region

## Read-only access to a HOME layer regardless of which region is swapped in
## (while a region is active, the home layers live in state.regions[_region]).
func home_layer(field: String) -> Variant:
	if _region == REGIONS.HOME:return state.get(field)
	return state.regions[_region].get(field)

## T055 self-only order board for `token` (Session sends it to that player
## only). Read-only: lazy expiry is shown but committed on the next order action.
func order_board(token: String) -> Dictionary:
	var person: Dictionary = state.players.get(token, {})
	if person.is_empty():return {}
	var now := float(state.time)
	var view := ORDER_CATALOG.snapshot(person.get("orders", {}), now, ORDER_CATALOG.context_from_world(self, token))
	view.board = state.get("board", false) == true
	return view

## T071 市集攤位格（可用在用戶端的家園快照上）；全被佔用時為 MARKET.NO_CELL。
static func market_cell(snapshot: Dictionary) -> Vector2i:
	return MARKET.cell_for(snapshot)

## T071 只給本人看的攤位摘要（Session 以 data.own_market 送出）。
func market_view(token: String) -> Dictionary:
	return MARKET.view(state,token,SHIPPING.prices(CROPS,FISH,OTHER_SALES))

## T071 豐收接力：場地是否可用（已解鎖且五格都空；可用在用戶端的家園快照上）。
static func harvest_available(snapshot: Dictionary) -> bool:
	return HARVEST.available(snapshot)

## T071 只給本人看的豐收接力摘要（Session 以 data.own_harvest 送出）。
func harvest_view(token: String) -> Dictionary:
	return HARVEST.view(state,token)

## T071 玩家離線：放下手上的模型蔬菜並退出這一輪（貢獻保留）。由 Session 在
## 玩家斷線時呼叫，Session 隨後存檔。有變更時回傳 true。
func harvest_disconnect(token: String) -> bool:
	return HARVEST.drop(state,token)

## T071 河岸釣魚會：場地是否可用（已解鎖且告示牌格空著；可用在用戶端的家園快照上）。
static func fish_meet_available(snapshot: Dictionary) -> bool:
	return FISH_MEET.available(snapshot)

## T071 只給本人看的河岸釣魚會摘要（Session 以 data.own_fish_meet 送出）。
func fish_meet_view(token: String) -> Dictionary:
	return FISH_MEET.view(state,token)

## T071 玩家離線：退出這一輪（貢獻保留，拋竿狀態不動）。由 Session 在玩家斷線時
## 呼叫，Session 隨後存檔。有變更時回傳 true。
func fish_meet_disconnect(token: String) -> bool:
	return FISH_MEET.drop(state,token)

## T071 家園布置題：場地是否可用（已解鎖且告示牌與展示地塊都空；可用在用戶端的家園快照上）。
static func showcase_available(snapshot: Dictionary) -> bool:
	return SHOWCASE.available(snapshot)

## T071 只給本人看的家園布置題摘要（Session 以 data.own_showcase 送出）。
func showcase_view(token: String) -> Dictionary:
	return SHOWCASE.view(state,token)

## T071 玩家離線：退出這一輪（放好的布置道具留在地塊上，貢獻保留）。由 Session 在
## 玩家斷線時呼叫，Session 隨後存檔。有變更時回傳 true。
func showcase_disconnect(token: String) -> bool:
	return SHOWCASE.drop(state,token)

## T071 紀念品交換攤格（可用在用戶端的家園快照上）；未解鎖或全被佔用時為 SOUVENIR.NO_CELL。
static func souvenir_cell(snapshot: Dictionary) -> Vector2i:
	return SOUVENIR.active_cell(snapshot)

## T071 只給本人看的紀念票餘額與兌換目錄（Session 以 data.own_souvenir 送出）。
func souvenir_view(token: String) -> Dictionary:
	return SOUVENIR.view(state,token)

func swap_region_layers(region: String) -> void:
	var other: Dictionary = state.regions[region]
	for field in REGIONS.LAYERS:
		var value = state[field]
		state[field] = other[field]
		other[field] = value

func regional_tokens() -> Array:
	return active_tokens.keys().filter(func(token): return player_region(token) == _region)

func step(dt: float, active: bool) -> bool:
	step_error = ""
	if not active:return true
	# Atomic tick: `before` is taken HOME-oriented (regional layers inside
	# state.regions), so _restore(before) -- which also resets _region to HOME --
	# always yields a consistently loaded projection. The loop below ends in
	# HOME anyway, so a successful tick is unchanged by this normalisation.
	switch_region(REGIONS.HOME)
	var before := state.duplicate(true)
	var undo_ticks_before := _undo_ticks_at.duplicate(true)
	var start: float = state.time
	var changed := false
	_undo_used = {}
	for region in REGIONS.ALL:
		switch_region(region)
		state.time = start
		var local_changed := step_region(dt)
		changed = changed or local_changed
	switch_region(REGIONS.HOME)
	var freight_changed := MINE_FREIGHT.step(state)
	var auto_changed:=MINE_AUTO_FREIGHT.step(state)
	var tea_changed:=TEA_CERAMICS.step(state)
	var market_changed:=MARKET.step(state,SHIPPING.prices(CROPS,FISH,OTHER_SALES))
	if HARVEST.step(state,active_tokens):market_changed=true # T071 豐收接力：離線放下、時間到結算
	if FISH_MEET.step(state,active_tokens):market_changed=true # T071 河岸釣魚會：離線退出、時間到結算
	if SHOWCASE.step(state,active_tokens):market_changed=true # T071 家園布置題：離線退出、時間到結算、冷卻後清空展示
	var livestock_changed:=LIVESTOCK.step(state.livestock,float(state.time),state.objects,dt)
	if LIVESTOCK.collect_into_equipment(state.livestock,float(state.time)):livestock_changed=true
	var livestock_chests:=LIVESTOCK.collect_into_chests(self)
	if not livestock_chests.is_empty():
		for key in livestock_chests:_undo_mark_remote_chest(_undo_used,REGIONS.HOME,{"cell":key})
		livestock_changed=true
	# Chapter 4 salt pans: exact event simulation over [start, start+dt]. The
	# active region is HOME here, so the beimen layers live in state.regions.
	# ok:false (bad shape/time, or MAX_EVENTS exceeded) means the salt interval
	# could not be simulated: the WHOLE tick fails. Time, every region, freight,
	# tea, undo history and `committed` return to `before`; nothing is saved.
	var salt_step:Dictionary=SALT_PAN.step(state,start,start+dt,state.regions[SALT_PAN.REGION].objects)
	if salt_step.get("ok",false)!=true:
		_step_rollback(before,undo_ticks_before,STEP_FAIL_SALT)
		return false
	var salt_changed:bool=salt_step.get("changed",false)==true
	_undo_mark_freight_uses(_undo_used,before)
	# T034: every tick transition is observed, even when nothing else is saved;
	# invalidation/expiry is persisted in the same save (or rolled back with it).
	var undo_changed:=_undo_observe(_undo_used)
	_undo_used = {}
	if changed or freight_changed or auto_changed or tea_changed or salt_changed or undo_changed or livestock_changed or market_changed:
		state.committed += 1
		if not save():
			_step_rollback(before,undo_ticks_before,STEP_FAIL_SAVE)
			return false
	_prune_undo_ticks()
	return true

## Restores a failed tick: HOME-oriented state snapshot (also _region=HOME),
## same-process undo ticks and the per-tick dependency scratch.
func _step_rollback(before: Dictionary, undo_ticks_before: Dictionary, code: String) -> void:
	_restore(before)
	_undo_ticks_at = undo_ticks_before
	_undo_used = {}
	step_error = code

func pump_rate() -> int:
	if _region == REGIONS.LANYANG and state.lanyang_life.repaired:
		return LANYANG_LIFE.REPAIRED_PUMP_RATE
	return INDUSTRY.PUMP_RATE

func step_region(dt: float) -> bool:
	var now:=float(state.time)+dt
	var water_plan:Dictionary={}
	var network_due:=now>=float(state.next_network_check)
	var tower_quota_plan:Dictionary={}
	if network_due:
		var network_plan:Dictionary=INDUSTRY.plan_detail(self,pump_rate())
		water_plan=network_plan.water
		tower_quota_plan=network_plan.quota
	# Settle crop-only time before selecting sprinkler targets: rain must not
	# mark an unused sprinkler as used, and midnight-dried plots need water now.
	var crop_start:=float(state.time)
	var crops_weathered:=step_crop_weather(crop_start,dt)
	var pending:=pending_sprinklers(now,water_plan)
	var forestry_due:=FORESTRY.due(state,now)
	var logistics_due:=now>=float(state.next_logistics_check)
	_undo_mark_step_uses(water_plan,pending,forestry_due,logistics_due)
	state.time += dt
	for k in state.forest:
		var tree:Dictionary=state.forest[k]
		if tree.mature:continue
		tree.growth=minf(float(tree.growth)+dt,TREE_TIME)
		if float(tree.growth)<TREE_TIME:continue
		var occupied:=false
		for token in regional_tokens():
			var who:Dictionary=state.players[token]
			if Vector2(who.x,who.y).distance_to(Vector2(cell(k))+Vector2(0.5,0.5))<0.8:occupied=true;break
		if not occupied:tree.mature=true
	if _region == "mine_3" and int(state.mine_depths.pumped)<24 and not water_plan.is_empty():
		for component in INDUSTRY.components(state):
			var has_pipe := false
			for device_key in component.keys:
				if state.objects[device_key].type == "water_pipe":has_pipe=true
			if not has_pipe:continue
			for tank in component.tanks:
				var gain := int(water_plan.get(tank,state.objects[tank].water))-int(state.objects[tank].water)
				if gain>0:state.mine_depths.pumped=mini(24,int(state.mine_depths.pumped)+gain)
	for device_key in water_plan:
		var device: Dictionary = state.objects[device_key]
		if INDUSTRY.SPRINKLER_CAPACITIES.has(device.type):
			var received := int(water_plan[device_key]) - int(device.water)
			if received > 0:
				device.network_water = int(device.get("network_water", 0)) + received
		device.water=water_plan[device_key]
	# 第 40 章定量配水：有每日配水的水塔記下當日已送出的量。
	for tower_key in tower_quota_plan:
		state.objects[tower_key].quota_day=int(tower_quota_plan[tower_key].day)
		state.objects[tower_key].quota_used=int(tower_quota_plan[tower_key].used)
	var watered:=step_sprinklers(pending)
	if network_due:
		state.next_network_check=now+INDUSTRY.INTERVAL
	if logistics_due:state.next_logistics_check=now+LOGISTICS.INTERVAL
	var logistics_plan:=LOGISTICS.plan(self,now,logistics_due)
	if not logistics_plan.is_empty():
		var used_here:Dictionary=_undo_used.get(_region,{})
		for device_key in logistics_plan:used_here[device_key]=true
		_undo_used[_region]=used_here
	for device_key in logistics_plan:
		var device:Dictionary=state.objects[device_key]
		var updated:Dictionary=logistics_plan[device_key]
		device.clear()
		device.merge(updated)
	var drill_changed:=MINE_DRILL.tick(state.objects,state.mine_depths,_region,now)
	var waterworks_changed:=WATERWORKS.tick(state.objects,now)
	var all_active := active_tokens
	active_tokens = {}
	for token in all_active:
		if player_region(token) == _region:active_tokens[token] = true
	var forest_work:=FORESTRY.cycle(self,forestry_due)
	active_tokens = all_active
	var cooking_changed:=step_cooking(now)
	var processing_changed:=step_processing(now)
	return crops_weathered or watered or not water_plan.is_empty() or forest_work or waterworks_changed or drill_changed or not logistics_plan.is_empty() or cooking_changed or processing_changed

## T039: advances every plot of the current region projection over world time
## [start, start+dt] using WEATHER's calendar-day rule (wetness ends at each game
## midnight; exposed plots are re-wetted by rain; growth only while wet, capped at
## maturity). Exposed = outdoor region and no roof on the tile, evaluated per tick
## so roof placement/removal applies on the next tick. Rain never consumes
## sprinkler water nor credits irrigation. Machines/queues keep their own dt
## rules; only crops are segmented by day here. Returns true when any plot's wet
## flag flipped, so rain/drying transitions are saved (or rolled back with step).
static func exploration_points(person:Dictionary) -> int:
	var discovered:Dictionary=person.get("explored_regions",{}).duplicate()
	discovered.merge(person.get("travel_book",{}).get("visited",{}))
	discovered.erase(REGIONS.HOME)
	return discovered.size()

static func exploration_level(points:int) -> int:
	for index in range(EXPLORATION_LEVEL_THRESHOLDS.size()-1,0,-1):
		if points>=EXPLORATION_LEVEL_THRESHOLDS[index]:return index+1
	return 1

static func _record_exploration(person:Dictionary,region:String) -> void:
	if region==REGIONS.HOME:return
	if not person.has("explored_regions"):person.explored_regions={}
	person.explored_regions[region]=true

static func build_area_limit(person:Dictionary) -> int:
	return CONSTRUCTION_HISTORY.MAX_AREA if crafting_level(person)>=BATCH_BUILD_LEVEL else BASIC_BUILD_AREA

static func crafting_level(person:Dictionary) -> int:
	var points:=int(person.get("crafting_points",0))
	for index in range(CRAFTING_LEVEL_THRESHOLDS.size()-1,0,-1):
		if points>=CRAFTING_LEVEL_THRESHOLDS[index]:return index+1
	return 1

static func gathering_level(person:Dictionary) -> int:
	var points:=int(person.get("gathering_points",0))
	for index in range(GATHERING_LEVEL_THRESHOLDS.size()-1,0,-1):
		if points>=GATHERING_LEVEL_THRESHOLDS[index]:return index+1
	return 1

static func farming_level(person:Dictionary) -> int:
	var points:=int(person.get("harvests",0))
	for index in range(FARMING_LEVEL_THRESHOLDS.size()-1,0,-1):
		if points>=FARMING_LEVEL_THRESHOLDS[index]:return index+1
	return 1

## T066 好感：居民所在的 [地區, 格子]。茶茶與星禾不在 Village.NPCS，站位沿用
## 茶園與水圳既有的互動格；介面與伺服器共用這一處判定。
static func bond_place(snapshot:Dictionary, resident:String) -> Array:
	if resident=="chacha":return [TEA_CERAMICS.MAOKONG,TEA_CERAMICS.TEA_NPC]
	if resident=="xinghe":return [REGIONS.LANYANG,LANYANG_LIFE.SERVICE]
	if resident=="mianmian":return [REGIONS.HOME,RESIDENT_BOND.ranch_cell(snapshot)]
	if resident=="achao":return [REGIONS.HOME,RESIDENT_BOND.dock_cell(snapshot)]
	if resident=="nuannuan":return [RESIDENT_BOND.SPRING_REGION,RESIDENT_BOND.SPRING_CELL]
	if resident=="luoluo":return [REGIONS.HOME,RESIDENT_BOND.post_cell(snapshot)]
	if resident=="lingpopo":return [REGIONS.HOME,RESIDENT_BOND.bell_cell(snapshot)]
	if resident=="diandian":return [RESIDENT_BOND.GARDEN_REGION,RESIDENT_BOND.GARDEN_CELL]
	return [Village.npc_region(resident),Village.resident_cell(snapshot,resident)]

static func crop_grows_in_season(kind:String, region:String, tile:Vector2i, time:float) -> bool:
	var seasons:Array=CROP_SEASONS.get(kind,[])
	return seasons.is_empty() or nursery_grows_year_round(kind,region,tile) or WEATHER.season_on_day(WEATHER.day_index(time)) in seasons

## Growth a regrowing crop restarts from after a harvest that leaves harvests: the plant
## stays, so only its "regrow" seconds are left (plan ch.09: every 2 days after the first
## ripening). Crops without "regrow" restart from 0.
static func regrow_start(kind:String) -> float:
	var crop:Dictionary=CROPS.get(kind,{})
	if not crop.has("regrow"):return 0.0
	return clampf(float(crop.time)-float(crop.regrow),0.0,float(crop.time))

## True while a planted, unripe crop is waiting for its season (plan ch.07: it keeps its
## growth and its remaining harvests). `roof` is the roof entry over the plot ({} if none).
## Ripe crops are never dormant: they stay harvestable in any season.
static func plot_dormant(crop:Dictionary, roof:Dictionary, region:String, tile:Vector2i, time:float) -> bool:
	var kind:=str(crop.get("kind",""))
	if not CROPS.has(kind) or float(crop.get("growth",0.0))>=float(CROPS[kind].time):return false
	if str(roof.get("type",""))=="greenhouse_roof":return false
	return not crop_grows_in_season(kind,region,tile,time)

## 「夏」「春、秋」… for a seasonal crop, "" for a year-round one.
static func crop_season_text(kind:String) -> String:
	var parts:PackedStringArray=[]
	for season:String in WEATHER.SEASONS:
		if season in CROP_SEASONS.get(kind,[]):parts.append(str(WEATHER.SEASON_LABELS[season]))
	return "、".join(parts)

static func nursery_grows_year_round(kind:String, region:String, tile:Vector2i) -> bool:
	return region==FLOWER_NURSERY.REGION and kind in FLOWER_NURSERY.FLOWERS and FLOWER_NURSERY.NURSERY_BEDS.has_point(tile)

func planting_problem(kind:String,tile:Vector2i)->String:
	if kind=="mist_tea" and (_region!=REGIONS.Bamboo.REGION or not REGIONS.Bamboo.TEA_BEDS.has_point(tile)):
		return "霧竹茶要種在溪谷茶圃"
	if _region==REGIONS.Bamboo.REGION and kind!="mist_tea":return "溪谷茶圃只種霧竹茶"
	if kind=="rice" and not REGIONS.rice_paddy(tile,_region):
		return "月牙稻米要種在宜蘭水圳旁的水田"
	if kind=="star_mushroom" and _region!="mine_5":
		return "星夜菇要種在金瓜石第五層的洞內菌床"
	return ""

func greenhouse_covers(tile_key:String) -> bool:
	return state.roofs.get(tile_key,{}).get("type","")=="greenhouse_roof"

func step_crop_weather(start:float,dt:float) -> bool:
	var changed:=false
	var indoor:=WEATHER.is_indoor(_region)
	for k in state.crops:
		var crop=state.crops[k]
		if not crop is Dictionary:continue
		var kind:=str(crop.get("kind",""))
		var need:=float(CROPS[kind].time) if CROPS.has(kind) else 0.0
		var was_wet:bool=crop.get("wet",false)==true
		# The cooperative nursery's teaching beds support its three flowers
		# year-round. Home plots still follow each crop's outdoor season.
		var year_round := nursery_grows_year_round(kind,_region,cell(k)) or greenhouse_covers(k)
		var result:Dictionary=WEATHER.advance_plot(was_wet,not indoor and not state.roofs.has(k),float(crop.get("growth",0.0)),need,start,dt,CROP_SEASONS.get(kind,[]),year_round)
		if need>0.0:crop.growth=float(result.growth)
		if bool(result.wet)!=was_wet:
			crop.wet=bool(result.wet)
			changed=true
	return changed

func can_harvest_plot(plot:Dictionary,token:String,machine:=false) -> bool:
	if plot.get("owner","")==token:return true
	if _region==FLOWER_NURSERY.REGION:return false
	var access:String=plot.get("harvest_access","owner" if machine else "island")
	return access=="island" or (access=="friend" and plot.get("harvest_friend","")==token)

func pending_sprinklers(now:float,water_plan:Dictionary) -> Dictionary:
	var pending:Dictionary={}
	for k in state.objects:
		var device:Dictionary=state.objects[k]
		if not INDUSTRY.SPRINKLER_CAPACITIES.has(device.type) or not device.enabled or int(water_plan.get(k,device.water))==0 or float(device.next_water)>now:
			continue
		var targets:Array[String]=[]
		for offset in INDUSTRY.sprinkler_offsets(device.type):
			var crop_key:=key(cell(k)+offset)
			var crop:Dictionary=state.crops.get(crop_key,{})
			if crop.get("kind","")!="" and not crop.get("wet",false) and crop.get("owner","")==device.owner:
				targets.append(crop_key)
		pending[k]=targets
	return pending

func step_sprinklers(pending:Dictionary) -> bool:
	var watered:=false
	for k in pending:
		var device:Dictionary=state.objects[k]
		for crop_key in pending[k]:
			if int(device.water)==0:break
			if state.crops[crop_key].wet:continue
			state.crops[crop_key].wet=true
			var network_water := int(device.get("network_water", 0))
			if network_water > 0 and network_water == int(device.water):
				device.network_water = network_water - 1
				CHAPTER_ONE.record_irrigation(state)
			device.water=int(device.water)-1
			device.last_water=float(state.time)
			watered=true
		device.next_water=float(state.time)+SPRINKLER_INTERVAL
	return watered

# ---------------------------------------------------------------------------
# T036 stove cooking queue (optional stove field `cooking`, CookingQueue state).
# A stove carries either the legacy single `job` or `cooking`, never both.
# ---------------------------------------------------------------------------

## Advances every queue-enabled stove of the current region projection to
## world time `now`. Malformed queues are left untouched (never replaced).
## Each stove that completed work is recorded as used for construction undo.
func step_cooking(now: float) -> bool:
	var changed:=false
	for k in state.objects:
		var stove=state.objects[k]
		if not stove is Dictionary or stove.get("type")!="stove" or not stove.has("cooking"):continue
		if stove.has("job") or not stove.cooking is Dictionary:continue
		var advanced:Dictionary=COOKING_QUEUE.advance(stove.cooking,RECIPES,now)
		if not advanced.ok or not advanced.changed:continue
		stove.cooking=advanced.state
		var used_here:Dictionary=_undo_used.get(_region,{})
		used_here[k]=true
		_undo_used[_region]=used_here
		changed=true
	return changed

## T036 manual sawmill/charcoal-kiln queues (optional device.processing).
## Same contract as step_cooking with the station-filtered INDUSTRY.PROCESS
## catalog. Invalid coexistence (job / auto mode) or malformed queues are left
## untouched. Completions mark the device used for construction undo.
func step_processing(now: float) -> bool:
	var changed:=false
	for k in state.objects:
		var device=state.objects[k]
		if not device is Dictionary or (str(device.get("type","")) not in LOGISTICS.PROCESSORS and device.get("type") not in ["seed_maker","loom","glass_furnace"]) or not device.has("processing"):continue
		if device.has("job") or device.get("auto_enabled",false) or not device.processing is Dictionary:continue
		var advanced:Dictionary=COOKING_QUEUE.advance(device.processing,processing_recipes(str(device.type)),now)
		if not advanced.ok or not advanced.changed:continue
		device.processing=advanced.state
		var used_here:Dictionary=_undo_used.get(_region,{})
		used_here[k]=true
		_undo_used[_region]=used_here
		changed=true
	return changed

## INDUSTRY.PROCESS entries whose station is `station` (fresh copy).
static func processing_recipes(station: String) -> Dictionary:
	if station=="seed_maker":return SEED_MAKER.recipes(CROPS)
	var out:={}
	for kind in INDUSTRY.PROCESS:
		var recipe:Dictionary=INDUSTRY.PROCESS[kind]
		if recipe.get("station","")==station:out[kind]=recipe.duplicate(true)
	return out

## True when the stove's queue holds no active, waiting or unclaimed ready work.
## Malformed queues count as busy so they can never be moved or removed away.
static func cooking_idle(stove: Dictionary) -> bool:
	var queue=stove.get("cooking")
	if not queue is Dictionary:return false
	var active=queue.get("active")
	var waiting=queue.get("waiting")
	var ready=queue.get("ready")
	return active is Dictionary and active.is_empty() and waiting is Array and waiting.is_empty() and ready is Array and ready.is_empty()

## Fresh unique lowercase 32-hex job id (not present in `queue`), "" on failure.
static func _cooking_new_id(queue: Dictionary) -> String:
	var taken:={}
	var active=queue.get("active",{})
	if active is Dictionary and active.has("id"):taken[active.id]=true
	for list_key in ["waiting","ready"]:
		for entry in queue.get(list_key,[]):
			if entry is Dictionary and entry.has("id"):taken[entry.id]=true
	var crypto:=Crypto.new()
	for attempt in 8:
		var id:=crypto.generate_random_bytes(16).hex_encode()
		if id.length()==COOKING_QUEUE.ID_LENGTH and not taken.has(id):return id
	return ""

## Every job id currently stored in any cooking or processing queue of every
## region (state.objects plus all state.regions layers covers both orientations).
func _queue_ids_global() -> Dictionary:
	var taken:={}
	var layers:Array=[state.get("objects",{})]
	var regions=state.get("regions",{})
	if regions is Dictionary:
		for region in regions.values():
			if region is Dictionary:layers.append(region.get("objects",{}))
	for layer in layers:
		if not layer is Dictionary:continue
		for obj in layer.values():
			if not obj is Dictionary:continue
			for field in ["cooking","processing"]:
				var queue=obj.get(field)
				if not queue is Dictionary:continue
				var active=queue.get("active",{})
				if active is Dictionary and active.get("id") is String:taken[active.id]=true
				for list_key in ["waiting","ready"]:
					var list=queue.get(list_key,[])
					if not list is Array:continue
					for entry in list:
						if entry is Dictionary and entry.get("id") is String:taken[entry.id]=true
	return taken

## Fresh 32-hex id unique within `queue` and across all queues of all regions.
func _queue_new_id(queue: Dictionary) -> String:
	var taken:=_queue_ids_global()
	for attempt in 8:
		var id:=_cooking_new_id(queue)
		if id!="" and not taken.has(id):return id
	return ""

## Replaces the live inventory contents in place so other references stay valid.
static func _cooking_commit_inventory(inv: Dictionary, items: Dictionary) -> void:
	inv.clear()
	inv.merge(items)

static func _cooking_ok(message: String, id: String, kind: String) -> Dictionary:
	return {"ok":true,"message":message,"id":id,"kind":kind}

## Queue-backed cook / queue_cook / claim_cook / cancel_cook / cancel_queued_cook.
## Runs inside act() in the actor's region after range/region/station checks.
## Nothing on the stove or inventory is written until every step succeeded, and
## act() additionally restores the whole pre-action state on any failure.
## Results carry only job id and recipe kind (never owners or tokens).
func _cooking_action(token: String, stove: Dictionary, action: String, extra: String) -> Dictionary:
	var player:Dictionary=state.players[token]
	var inv:Dictionary=player.inventory
	var now:=float(state.time)
	if action in ["cook","queue_cook"]:
		if not RECIPES.has(extra):return fail("還沒有這份食譜")
		var base:Dictionary
		if stove.has("cooking"):
			if not stove.cooking is Dictionary:return fail(COOKING_MSG_CORRUPT)
			var caught_up:Dictionary=COOKING_QUEUE.advance(stove.cooking,RECIPES,now)
			if not caught_up.ok:return fail(COOKING_MSG_CORRUPT)
			base=caught_up.state
		elif stove.has("job"):
			# Lazy legacy import: committed only together with the new enqueue.
			if not stove.job is Dictionary:return fail(COOKING_MSG_CORRUPT)
			var import_id:=_queue_new_id({})
			if import_id=="":return fail(COOKING_MSG_CORRUPT)
			var imported:Dictionary=COOKING_QUEUE.import_legacy(stove.job,RECIPES,now,import_id)
			if not imported.ok:return fail(str(imported.message))
			base=imported.state
		else:
			base=COOKING_QUEUE.empty_state()
		var total:=(0 if (base.active as Dictionary).is_empty() else 1)+(base.waiting as Array).size()+(base.ready as Array).size()
		if total>=COOKING_QUEUE.CAPACITY:return fail("石灶排程已滿（最多 %d 份），請先領取或等候"%COOKING_QUEUE.CAPACITY)
		var recipe:Dictionary=RECIPES[extra]
		for item in recipe.ingredients:
			if int(inv.get(item,0))<int(recipe.ingredients[item]):return fail("缺少"+str(NAMES.get(item,item))+" %d"%int(recipe.ingredients[item]))
		var id:=_queue_new_id(base)
		if id=="":return fail(COOKING_MSG_CORRUPT)
		var queued:Dictionary=COOKING_QUEUE.enqueue(base,RECIPES,now,token,extra,id,inv)
		if not queued.ok:return fail(str(queued.message))
		_cooking_commit_inventory(inv,queued.inventory)
		stove.cooking=queued.state
		stove.erase("job")
		var message:String=recipe.name+("開始製作" if queued.started else "已排入石灶（共 %d 份）"%(total+1))+"，完成後任何成員都能領取"
		var result:=_cooking_ok(message,id,extra)
		result.started=bool(queued.started)
		return result
	if not stove.has("cooking"):return fail("石灶目前沒有料理排程")
	if not stove.cooking is Dictionary:return fail(COOKING_MSG_CORRUPT)
	var advanced:Dictionary=COOKING_QUEUE.advance(stove.cooking,RECIPES,now)
	if not advanced.ok:return fail(COOKING_MSG_CORRUPT)
	var queue:Dictionary=advanced.state
	var active:Dictionary=queue.active
	if action=="claim_cook":
		if (queue.ready as Array).is_empty():
			if active.is_empty():return fail("石灶現在沒有料理")
			return fail("還要 %d 秒就好了"%ceili(float(active.finish)-now))
		var claimed:Dictionary=COOKING_QUEUE.claim(queue,RECIPES,now,inv)
		if not claimed.ok:return fail("背包中的料理已達上限，請先騰出空間再領取" if str(claimed.message).contains("上限") else str(claimed.message))
		var kind:String=claimed.kind
		_cooking_commit_inventory(inv,claimed.inventory)
		stove.cooking=claimed.state
		if Collections.is_meal(kind):_record_discovery(player,"meals",kind)
		player.cooked=int(player.get("cooked",0))+1
		var claim_result:=_cooking_ok("完成了！%s +%d"%[RECIPES[kind].name,int(claimed["yield"])],str(claimed.id),kind)
		claim_result["yield"]=int(claimed["yield"])
		return claim_result
	var target:=""
	if action=="cancel_cook":
		if active.is_empty():return fail("石灶現在沒有進行中的料理" if (queue.ready as Array).is_empty() else "料理已完成，無法取消，請直接領取")
		if active.owner!=token:return fail("只有投入食材的人可以取消")
		target=str(active.id)
	elif action=="cancel_queued_cook":
		if not _is_lower_hex(extra,COOKING_QUEUE.ID_LENGTH):return fail("找不到這份料理")
		target=extra
	else:
		return fail("請選擇工具後再試一次")
	var cancelled:Dictionary=COOKING_QUEUE.cancel(queue,RECIPES,now,token,target,inv)
	if not cancelled.ok:
		var reason:=str(cancelled.message)
		return fail("背包中的食材已達上限，請先騰出空間再取消" if reason.contains("上限") else reason)
	_cooking_commit_inventory(inv,cancelled.inventory)
	stove.cooking=cancelled.state
	var cancel_result:=_cooking_ok("已取消，食材完整退回",target,str(cancelled.kind))
	cancel_result.refunded=(cancelled.refunded as Dictionary).duplicate()
	return cancel_result

func move_player(token: String, direction: Vector2, dt: float) -> void:
	if not state.players.has(token): return
	var p: Dictionary = state.players[token]
	var pos := Vector2(p.x, p.y)
	switch_region(player_region(token))
	var next := pos + direction.limit_length()*3.6*dt
	if direction.length_squared()>0.01:p.erase("fishing")
	# Separate axes; corners of a small foot box must all remain passable.
	if can_stand(Vector2(next.x,pos.y)): pos.x=next.x
	if can_stand(Vector2(pos.x,next.y)): pos.y=next.y
	p.x=pos.x
	p.y=pos.y
	switch_region(REGIONS.HOME)

func can_stand(pos: Vector2) -> bool:
	for offset in [Vector2(-0.22,-0.17),Vector2(0.22,-0.17),Vector2(-0.22,0.17),Vector2(0.22,0.17)]:
		var v: Vector2=pos+offset
		if blocked(Vector2i(floori(v.x),floori(v.y))): return false
	return true

func act(token: String, request_id: String, action: String, p: Vector2i, extra: String="") -> Dictionary:
	if not state.players.has(token): return {"ok":false,"message":"尚未加入世界"}
	if request_id.length()<1 or request_id.length()>80: return {"ok":false,"message":"無效請求"}
	var build_style := ""
	if action in ["build","build_area"] and extra.contains("@"):
		var parts := extra.split("@")
		if parts.size()!=2 or BUILD_STYLES.entry(parts[1]+"."+parts[0].get_slice("|",0)).is_empty():return fail("無效的建築風格")
		extra=parts[0]
		build_style=parts[1]
	# Normalize to home orientation so `before` is always a home-oriented snapshot
	# (regional layers live in state.regions) and restoring it is unambiguous.
	switch_region(REGIONS.HOME)
	var player: Dictionary=state.players[token]
	if player.receipts.has(request_id): return player.receipts[request_id]
	var before := state.duplicate(true)
	var region := player_region(token)
	var builds_before:=int(player.get("builds",0))
	switch_region(region)
	# Decided BEFORE the base action: remove must know what it is about to target.
	var touched := _auto_roof_touched(action,p,extra)
	var undo_intent := _undo_intent(action,p,extra)
	var quest_types := _undo_quest_types(token,action,extra)
	var result: Dictionary
	if action in TRADE_ACTIONS:result=_trade_action(token,request_id,action,extra)
	elif action==UNDO_ACTION:result=_undo_apply(token,extra)
	else:result=_apply(token,action,p,extra,build_style)
	if result.ok and action=="build" and not build_style.is_empty():
		var layer := BUILD_STYLES.expected_layer(extra)
		state[layer][key(p)].style=build_style
	if not result.ok:
		switch_region(REGIONS.HOME)
		# Most rejected base actions have not mutated anything. Keep their live
		# references intact; only replace state when rollback is actually needed.
		if state!=before:_restore(before)
		_ledger_reject(action,token,request_id,str(result.get("message","")))
		return result
	if result.ok and not touched.is_empty():
		var roof := _reconcile_auto_roofs(token,region,before,touched)
		if not roof.ok:
			_restore(before)
			_ledger_reject(action,token,request_id,str(roof.message))
			return fail(str(roof.message))
		if int(roof.added)>0 or int(roof.removed)>0:
			result.roof_add_count=int(roof.added)
			result.roof_remove_count=int(roof.removed)
			result.message=str(result.message)+"；"+str(roof.summary)
	switch_region(REGIONS.HOME)
	var staged_trade: Dictionary = result.get("staged_trade", {})
	result.erase("staged_trade")
	if action=="survey_observe" and result.get("unchanged",false):return result
	if result.ok:
		# T034, same transaction as base action + auto roofs + receipt + save:
		# observe older records first, then capture this construction.
		var used:Dictionary={}
		if action!=UNDO_ACTION and undo_intent.is_empty():
			_undo_mark_act_uses(used,token,region,p,quest_types,before)
		_undo_mark_freight_uses(used,before,token,action)
		# T042: registration permanently uses all three donated HOME cells, so every
		# live undo record (the donor's own or anyone's) watching them is closed in
		# this same transaction. Records not watching these tiles stay untouched.
		if action==PUBLIC_KITCHEN.REGISTER:
			var kitchen_tiles:Dictionary=used.get(REGIONS.HOME,{})
			for c in PUBLIC_KITCHEN.site_cells(state):kitchen_tiles[key(c)]=true
			used[REGIONS.HOME]=kitchen_tiles
		# T036: prepare_material_box and sourced commits explicitly use the chosen
		# chest (in the actor's region) even when it looks unchanged.
		if (action==MATERIAL_SOURCES.PREPARE_ACTION or action in MATERIAL_SOURCES.ACTIONS) and result.get("source_cell") is String:
			_undo_mark_remote_chest(used,region,{"cell":result.source_cell})
		_undo_observe(used)
		if not undo_intent.is_empty():
			_undo_capture(token,region,action,str(undo_intent.label),before,builds_before)
		player=state.players[token]
		state.committed += 1
		player.receipts[request_id]=result
		# Keep a bounded retry window; transport session IDs reject old sessions.
		while player.receipts.size()>128: player.receipts.erase(player.receipts.keys()[0])
		# T015: the journal entry lives in the same state save() writes, so the
		# change, its receipt and its journal row commit (or roll back) together.
		var journal_entry:=_ledger_commit(action,token,request_id,before,result)
		if not save():
			_restore(before)
			if not journal_entry.is_empty():_ledger_reject(action,token,request_id,SAVE_FAILED_MSG,true)
			return {"ok":false,"message":SAVE_FAILED_MSG}
		_ledger_pending.clear()
		if not staged_trade.is_empty():
			if TRADE.is_open(staged_trade):trade_offers[staged_trade.id]=staged_trade
			else:trade_offers.erase(staged_trade.id)
		if action in ["travel","transit","mine_travel"] or player_region(token)!=region:
			cancel_trades(token)
	_prune_undo_ticks()
	return result

const SAVE_FAILED_MSG := "保存失敗，這次操作未提交。請先檢查儲存空間。"

## T015: appends this commit's journal row (if it is an economy transaction)
## plus pending rejections to the live state, right before the commit's save().
## Must run with HOME orientation, after state.committed and the receipt are set.
## A completed trade_confirm whose settlement was refused (inventory full) is a
## rejected trade: it is journaled as a rejection in this same commit.
func _ledger_commit(action: String, token: String, request_id: String, before: Dictionary, result: Dictionary) -> Dictionary:
	if result.get("trade_refused",false)==true:
		_ledger_reject(action,token,request_id,str(result.get("message","")),true)
	var entry:=TRANSACTION_LEDGER.committed_entry(action,token,request_id,before,state)
	TRANSACTION_LEDGER.append(state,entry,_ledger_pending,float(state.get("time",0.0)))
	return entry

## T015: remembers a refused economy request (bounded, in memory) so the next
## committed request saves it. Never touches `state` here: a refusal must leave
## the world exactly as it was.
func _ledger_reject(action: String, token: String, request_id: String, message: String, force: bool=false) -> void:
	if not force and not TRANSACTION_LEDGER.is_economy_action(action):return
	_ledger_pending.append(TRANSACTION_LEDGER.rejected_entry(action,token,request_id,message,float(state.get("time",0.0))))
	while _ledger_pending.size()>TRANSACTION_LEDGER.PENDING_CAP:_ledger_pending.pop_front()

## T015 read API (server side): journal rows `token` may see, as copies. Never
## exposes raw tokens or other players' private boxes (TransactionLedger.view).
func ledger_view(token: String, limit: int=64) -> Array:
	return TRANSACTION_LEDGER.view(state,token,limit)

func cancel_trades(token: String) -> void:
	for id in trade_offers.keys():
		if TRADE.involves(trade_offers[id],token):trade_offers.erase(id)

func trade_view(token: String) -> Dictionary:
	for offer: Dictionary in trade_offers.values():
		if TRADE.involves(offer,token) and not TRADE.expired(offer,Time.get_unix_time_from_system()):
			return TRADE.view(offer,token)
	return {}

func _trade_action(token: String, request_id: String, action: String, extra: String) -> Dictionary:
	var now := Time.get_unix_time_from_system()
	for id in trade_offers.keys():
		if TRADE.expired(trade_offers[id],now):trade_offers.erase(id)
	var parsed: Dictionary = {}
	var result: Dictionary
	if action=="trade_open":
		if not active_tokens.has(extra) or not _trade_near(token,extra):return fail("請靠近要交易的島民。")
		if not trade_view(token).is_empty() or not trade_view(extra).is_empty():return fail("有島民正在交易。")
		result=TRADE.open(request_id,token,extra,now)
	else:
		if action=="trade_edit":parsed=TRADE.parse_edit(extra)
		elif action=="trade_confirm":parsed=TRADE.parse_confirm(extra)
		else:parsed={"ok":true,"offer_id":extra}
		if not parsed.ok:return fail(parsed.message)
		var offer: Dictionary = trade_offers.get(parsed.offer_id,{})
		if offer.is_empty():return fail(TRADE.MSG_CLOSED)
		var partner := TRADE.other_party(offer,token)
		if partner.is_empty():return fail(TRADE.MSG_NOT_PARTY)
		if action=="trade_cancel":
			result=TRADE.cancel(offer,token,TRADE.REASON_PLAYER)
		elif not active_tokens.has(partner) or not _trade_near(token,partner):
			return fail("請靠近要交易的島民。")
		elif action=="trade_edit":
			var person: Dictionary = state.players[token]
			result=TRADE.set_side(offer,token,parsed.lines,parsed.coins,trade_items(),person.inventory,person.coins)
		else:
			result=TRADE.confirm(offer,token,parsed.revision)
			if result.ok and TRADE.is_ready(result.offer):
				var a: Dictionary = state.players[offer.a]
				var b: Dictionary = state.players[offer.b]
				result=TRADE.stage_settlement(result.offer,a,b,trade_items())
				if result.ok:
					a.inventory=result.a.inventory
					a.coins=result.a.coins
					b.inventory=result.b.inventory
					b.coins=result.b.coins
	if not result.ok and not result.get("cancelled",false):return fail(result.message)
	return {"ok":true,"message":result.message,"staged_trade":result.offer,"trade_refused":not result.ok}

static func trade_items() -> Dictionary:
	var items := NAMES.duplicate()
	for item in ["gold_sample","reinforced_pick","tiller","seeder","harvester"]:
		items.erase(item)
	for item in SOUVENIR.items():items.erase(item) # T071 紀念票兌換品不能交易（不是換鈴幣的管道）
	for item in RESIDENT_GOALS.keepsake_items():items.erase(item) # T066 居民紀念小物是個人紀念，不能交易
	items.erase(LANYANG_REVISIT.PLAQUE_ITEM) # 第 40 章分水木牌是個人紀念，不能交易
	items.erase(JINGUASHI_REVISIT.LANTERN_ITEM) # 第 40 章礦燈是個人紀念，不能交易
	items.erase(TEA_REVISIT.TEAWARE_ITEM) # 第 40 章茶陶組是個人紀念，不能交易
	items.erase(SALT_REVISIT.BASKET_ITEM) # 第 40 章鹽籃是個人紀念，不能交易
	return items

func _trade_near(token: String, partner: String) -> bool:
	if not state.players.has(partner) or player_region(token)!=player_region(partner):return false
	var a: Dictionary = state.players[token]
	var b: Dictionary = state.players[partner]
	return Vector2(a.x,a.y).distance_to(Vector2(b.x,b.y))<=3.2

## Discards the working state (whatever its orientation) and reinstates the
## home-oriented snapshot taken at the start of act().
func _restore(before: Dictionary) -> void:
	state=before
	_region=REGIONS.HOME

## Tiles whose topology the action may change; empty when the action can never
## affect automatic roofs (furniture, paths, farming, moves, doors toggling...).
## Must be called in the actor's region BEFORE _apply.
func _auto_roof_touched(action: String, p: Vector2i, extra: String) -> Array[Vector2i]:
	var touched: Array[Vector2i] = []
	if action=="build":
		if extra in AUTO_ROOF_BUILDS:touched.append(p)
	elif action=="build_area":
		var parts:=extra.split("|")
		if parts.size()!=3 or parts[0] not in AUTO_ROOF_AREAS or not parts[1].is_valid_int() or not parts[2].is_valid_int():return touched
		var end:=Vector2i(int(parts[1]),int(parts[2]))
		if abs(end.x)>1000 or abs(end.y)>1000:return touched
		var a:=Vector2i(mini(p.x,end.x),mini(p.y,end.y))
		var b:=Vector2i(maxi(p.x,end.x),maxi(p.y,end.y))
		var count:=(b.x-a.x+1)*(b.y-a.y+1)
		if count>CONSTRUCTION_HISTORY.MAX_AREA or count<1:return touched
		for y in range(a.y,b.y+1):
			for x in range(a.x,b.x+1):touched.append(Vector2i(x,y))
	elif action=="remove":
		var k:=key(p)
		if state.forest.has(k) or state.crops.has(k):return touched
		var layer:=_remove_layer(k)
		# Manual roof edits preserve the original per-tile control and price.
		if layer!="" and layer!="roofs":
			var target=state[layer][k]
			if target is Dictionary and str(target.get("type","")) in AUTO_ROOF_REMOVES:touched.append(p)
	return touched

static func is_auto_roof(roof) -> bool:
	if not (roof is Dictionary):return false
	var flag=roof.get("auto")
	return typeof(flag)==TYPE_BOOL and flag

## Which current-region layer `remove` targets at k: manual roofs first (as
## before), automatic roofs are skipped so the owner of the object/floor below
## keeps control under the usual guards. "" when nothing is removable.
func _remove_layer(k: String) -> String:
	if state.roofs.has(k) and not is_auto_roof(state.roofs[k]):return "roofs"
	if state.objects.has(k):return "objects"
	if state.ground.has(k):return "ground"
	return ""

## Runs in the actor's region after a successful base action. Plans the roof
## delta with the pure planner, validates every affected inventory, then applies
## roofs + staged inventories together. Returns {ok, message} on failure (caller
## restores `before`), or {ok, added, removed, summary}.
func _reconcile_auto_roofs(token: String, region: String, before: Dictionary, touched: Array[Vector2i]) -> Dictionary:
	var source: Dictionary = before if region==REGIONS.HOME else before.regions.get(region,{})
	if source.is_empty() and region!=REGIONS.HOME:return {"ok":false,"message":"區域資料有誤，這次沒有施工"}
	var prior := {"ground":source.get("ground",{}),"objects":source.get("objects",{}),"roofs":source.get("roofs",{})}
	var after := {"ground":state.ground,"objects":state.objects,"roofs":state.roofs}
	var plan:Dictionary=AUTO_ROOF_PLAN.reconcile(prior,after,touched,token,BUILD.roof)
	if not plan.ok:return {"ok":false,"message":plan.message}
	var add:Dictionary=plan.add
	var remove:Array=plan.remove
	if add.is_empty() and remove.is_empty():return {"ok":true,"added":0,"removed":0,"summary":""}
	if not state.players.has(token):return {"ok":false,"message":"無法確認付款者，這次沒有施工"}
	for roof_key in add:
		var base=state.ground.get(roof_key)
		var roof=add[roof_key]
		if state.roofs.has(roof_key) or not (base is Dictionary) or str(base.get("type",""))!="floor":return {"ok":false,"message":"屋頂施工計畫有誤，這次沒有施工"}
		if typeof(base.get("owner"))!=TYPE_STRING or not state.players.has(base.owner):return {"ok":false,"message":"地板資料有誤，這次沒有施工"}
		if not (roof is Dictionary) or roof.get("owner")!=token or not is_auto_roof(roof) or roof.get("type")!="roof":return {"ok":false,"message":"屋頂施工計畫有誤，這次沒有施工"}
	for roof_key in remove:
		if not is_auto_roof(state.roofs.get(roof_key)):return {"ok":false,"message":"屋頂施工計畫有誤，這次沒有施工"}
	var settled:Dictionary=AUTO_ROOF_SETTLEMENT.prepare(state.players,token,plan)
	if not settled.ok:return {"ok":false,"message":settled.message}
	# Everything validated: apply as one unit (persisted by act's single save).
	for roof_key in remove:state.roofs.erase(roof_key)
	for roof_key in add:state.roofs[roof_key]=add[roof_key].duplicate(true)
	var staged:Dictionary=settled.inventories
	for owner in staged:state.players[owner].inventory=staged[owner]
	return {"ok":true,"added":add.size(),"removed":remove.size(),"summary":_auto_roof_summary(token,plan)}

## Short player-facing summary; never contains payer identities.
static func _auto_roof_summary(token: String, plan: Dictionary) -> String:
	var parts:PackedStringArray=[]
	if not plan.add.is_empty():
		parts.append("自動蓋上屋頂 %d 格（%s）"%[plan.add.size(),_amounts(plan.cost,"−")])
	if not plan.remove.is_empty():
		var text:="拆除自動屋頂 %d 格"%plan.remove.size()
		var refunds:Dictionary=plan.refunds
		if refunds.has(token):text+="，退回你%s"%_amounts(refunds[token],"+")
		var others:=refunds.size()-(1 if refunds.has(token) else 0)
		if others>0:text+="，另有 %d 位原出資者收到退料"%others
		parts.append(text)
	return "；".join(parts)

static func _amounts(counts: Dictionary, mark: String) -> String:
	var names:Array=counts.keys()
	names.sort()
	var out:PackedStringArray=[]
	for item in names:out.append("%s %s%d"%[NAMES.get(item,item),mark,int(counts[item])])
	return "、".join(out)

# ---------------------------------------------------------------------------
# T034 construction undo (server-authoritative; history is server-only)
# ---------------------------------------------------------------------------

const UNDO_MSG_REGION := "回到施工的地區才能復原"
const UNDO_MSG_NOT_LAST := "這筆施工已不是你最後一次施工，無法復原"
const UNDO_MSG_MISSING := "找不到這筆施工紀錄，請重新整理後再試"
const UNDO_MSG_TERRAIN := "原位置已無法使用，無法復原"
const UNDO_MSG_ROOF := "屋頂下方的地板已不同，無法復原"
const UNDO_MSG_TOPOLOGY := "復原後房間屋頂會不一致，無法復原"
const UNDO_MSG_LIMIT := "復原後會超過設備數量上限，無法復原"
const UNDO_MSG_OCCUPIED := "有人站在要復原的位置，請先移開"
const UNDO_MSG_STATS := "施工紀錄與統計不一致，無法復原"
const UNDO_MSG_LOCKED := "這項設備目前無法放回原位，無法復原"
const UNDO_FOOT := [Vector2(-0.22,-0.17),Vector2(0.22,-0.17),Vector2(-0.22,0.17),Vector2(0.22,0.17)]

## UTC epoch seconds from the injected clock when it is a valid Callable, else
## Time. An injected clock returning a non-finite/out-of-range value yields -1
## (treated as a clock failure, never as "now").
func _undo_utc() -> float:
	if undo_clock_utc.is_valid():
		var value=undo_clock_utc.call()
		if (value is float or value is int) and is_finite(float(value)) and float(value)>0.0 and float(value)<=CONSTRUCTION_HISTORY.MAX_UTC:return float(value)
		return -1.0
	return Time.get_unix_time_from_system()

## Monotonic msec from the injected clock when valid, else Time; -1 on failure.
func _undo_ticks() -> int:
	if undo_clock_ticks.is_valid():
		var value=undo_clock_ticks.call()
		if value is int:return value if value>=0 else -1
		if value is float and is_finite(value) and value>=0.0 and floorf(value)==value and value<9.0e15:return int(value)
		return -1
	return Time.get_ticks_msec()

## The live history dictionary, or {} when malformed (never repaired silently).
func _history(create: bool = false) -> Dictionary:
	if create and not state.has("construction"):state.construction=CONSTRUCTION_HISTORY.fresh()
	var hist=state.get("construction")
	if not hist is Dictionary or not hist.get("last") is Dictionary:return {}
	var serial=hist.get("serial")
	if not (serial is int or serial is float) or not is_finite(float(serial)) or float(serial)<0.0 or floorf(float(serial))!=float(serial):return {}
	return hist

## Region-local layers regardless of the current projection orientation.
func _layers_of(region: String) -> Dictionary:
	var source=state
	if region!=_region:
		var regions=state.get("regions",{})
		source=regions.get(_region if region==REGIONS.HOME else region,{}) if regions is Dictionary else {}
	var out:={}
	for field in CONSTRUCTION_HISTORY.TILE_LAYERS:
		var layer=source.get(field,{}) if source is Dictionary else {}
		out[field]=layer if layer is Dictionary else {}
	return out

## {label} when the action is an undoable construction attempt, else {}.
## Called in the actor's region BEFORE _apply. Sapling/crop removal is excluded.
func _undo_intent(action: String, p: Vector2i, extra: String) -> Dictionary:
	var k:=key(p)
	match action:
		"build":
			if BUILD.has(extra):return {"label":str(BUILD[extra].name)}
		"build_area":
			var parts:=extra.split("|")
			if parts.size()==3 and BUILD.has(parts[0]):return {"label":str(BUILD[parts[0]].name)}
		"remove":
			if state.forest.has(k) or (state.crops.has(k) and not greenhouse_covers(k)):return {}
			var layer:=_remove_layer(k)
			if layer=="":return {}
			var target=state[layer][k]
			if target is Dictionary:return {"label":"拆除"+str(BUILD.get(str(target.get("type","")),{}).get("name","建物"))}
		"move_object":
			var obj=state.objects.get(k)
			if obj is Dictionary:return {"label":"搬移"+str(BUILD.get(str(obj.get("type","")),{}).get("name","家具"))}
	return {}

## Object types a quest submission is about to rely on (Village.blocked_reason).
func _undo_quest_types(token: String, action: String, extra: String) -> Array:
	if action!="quest":return []
	var parts:=extra.split(":")
	if parts.size()!=2 or not Village.QUESTS.has(parts[0]):return []
	var stories=state.players[token].get("stories",{})
	var stage:=int(stories.get(parts[0],0)) if stories is Dictionary else 0
	var quests:Array=Village.QUESTS[parts[0]]
	if stage<0 or stage>=quests.size():return []
	var types:=[]
	for field in ["object","second_object"]:
		if quests[stage].has(field):types.append(str(quests[stage][field]))
	return types

## Explicit uses by a successful non-construction act: an object at the target
## tile (bench craft, stove, chest, device, door...) and every own object a quest
## submission relied on. Plain harvesting/gathering touches no object.
func _undo_mark_act_uses(used: Dictionary, token: String, region: String, p: Vector2i, quest_types: Array, before: Dictionary) -> void:
	var tile:=key(p)
	var layers:=_layers_of(region)
	var source:Dictionary=before if region==REGIONS.HOME else before.regions.get(region,{})
	var prior=source.get("objects",{})
	var tiles:Dictionary=used.get(region,{})
	if layers.objects.has(tile) or (prior is Dictionary and prior.has(tile)):tiles[tile]=true
	if not quest_types.is_empty():
		for k in layers.objects:
			var obj=layers.objects[k]
			if obj is Dictionary and obj.get("owner")==token and str(obj.get("type","")) in quest_types:tiles[k]=true
	if not tiles.is_empty():used[region]=tiles

## Tick uses that may leave the used tile itself unchanged: water flowing
## through a network (all members incl. unchanged pipes), sprinklers watering,
## due forestry stations, and enabled conveyors with their same-owner front/rear.
## Runs in the stepped region's orientation BEFORE the tick mutates anything.
func _undo_mark_step_uses(water_plan: Dictionary, pending: Dictionary, forestry_due: Array[String], logistics_due: bool) -> void:
	var used_here:Dictionary=_undo_used.get(_region,{})
	var flowing:={}
	for k in water_plan:flowing[k]=true
	for k in pending:
		if not (pending[k] as Array).is_empty():flowing[k]=true
	if not flowing.is_empty():
		for component in INDUSTRY.components(state):
			var hit:=false
			for k in component["keys"]:
				if flowing.has(k):
					hit=true
					break
			if hit:
				for k in component["keys"]:used_here[k]=true
	for k in forestry_due:used_here[k]=true
	if logistics_due:
		for k in state.objects:
			var belt:Dictionary=state.objects[k]
			if belt.get("type")!="conveyor" or not belt.get("enabled",false):continue
			used_here[k]=true
			var offset:Vector2i=LOGISTICS.DIRECTIONS[int(belt.dir)]
			for n in [cell(k)+offset,cell(k)-offset]:
				var nk:=key(n)
				var other=state.objects.get(nk)
				if other is Dictionary and other.get("owner")==belt.owner:used_here[nk]=true
	if not used_here.is_empty():_undo_used[_region]=used_here

# Freight references a remote chest by cell/id. Re-selecting a registered
# destination, or dispatching to it, need not mutate the chest itself.
func _undo_mark_freight_uses(used:Dictionary,before:Dictionary,actor:String="",action:String="") -> void:
	var old_jobs:Dictionary=before.get("mine_freight",{}).get("jobs",{})
	var jobs:Dictionary=state.mine_freight.jobs
	for owner in jobs:
		var explicit_use:bool=owner==actor and action in ["freight_target","freight_dispatch"]
		if explicit_use or jobs[owner]!=old_jobs.get(owner,{}):
			_undo_mark_remote_chest(used,REGIONS.HOME,jobs[owner].get("target",{}))
	if action in MINE_AUTO_FREIGHT.ACTIONS:
		for routes in [before.get("mine_auto_freight",{}).get("routes",{}),state.mine_auto_freight.routes]:
			var route:Dictionary=routes.get(actor,{})
			_undo_mark_remote_chest(used,REGIONS.HOME,route.get("target",{}))
			_undo_mark_remote_chest(used,str(route.get("region","")),route.get("source",{}))

func _undo_mark_remote_chest(used:Dictionary,region:String,endpoint:Dictionary)->void:
	if region not in REGIONS.ALL:return
	var tile=str(endpoint.get("cell",""))
	if not CONSTRUCTION_HISTORY.parse_tile(tile).ok:return
	var tiles:Dictionary=used.get(region,{})
	tiles[tile]=true
	used[region]=tiles

## {ok, code, left}: UTC window (persisted) plus same-process monotonic window.
## A clock earlier than the creation time is a rollback and fails.
func _undo_time(entry: Dictionary) -> Dictionary:
	var now:=_undo_utc()
	if now<0.0 or now<float(entry.created_utc):return {"ok":false,"code":"clock","left":0.0}
	var left:=float(entry.expires_utc)-now
	if left<=0.0:return {"ok":false,"code":"expired","left":0.0}
	if _undo_ticks_at.has(entry.id):
		var ticks:=_undo_ticks()
		var at:int=int(_undo_ticks_at[entry.id])
		if ticks<0 or ticks<at:return {"ok":false,"code":"clock","left":0.0}
		var mono:=float(CONSTRUCTION_HISTORY.WINDOW_MSEC-(ticks-at))/1000.0
		if mono<=0.0:return {"ok":false,"code":"expired","left":0.0}
		left=minf(left,mono)
	return {"ok":true,"code":"","left":minf(left,CONSTRUCTION_HISTORY.WINDOW_SECONDS)}

## Permanently closes an entry; the private payload is dropped.
func _undo_close(entry: Dictionary, code: String) -> void:
	entry.status="consumed" if code=="consumed" else ("expired" if code=="expired" else "invalid")
	entry.reason=code
	entry.record={}
	entry.watch={}

## Observes every live record against the current world. Returns true when any
## entry changed (caller persists it in the same save / rolls it back with it).
func _undo_observe(used: Dictionary) -> bool:
	var hist:=_history()
	if hist.is_empty():return false
	var last:Dictionary=hist.last
	var changed:=false
	for token in last.keys():
		var entry=last[token]
		if entry is Dictionary and entry.get("status")!="live":continue
		if not CONSTRUCTION_HISTORY.entry_basic(entry) or not REGIONS.ALL.has(entry.region):
			last.erase(token)
			changed=true
			continue
		var timing:=_undo_time(entry)
		if not timing.ok:
			_undo_close(entry,str(timing.code))
			changed=true
		elif CONSTRUCTION_HISTORY.watch_used(entry.watch,used.get(entry.region,{})):
			_undo_close(entry,"used")
			changed=true
		elif not CONSTRUCTION_HISTORY.watch_matches(_layers_of(entry.region),entry.watch):
			_undo_close(entry,"changed")
			changed=true
	return changed

## Records the actor's LAST construction after a successful build/build_area/
## remove/move_object (base + auto roofs already applied, oriented HOME). Any
## capture problem still replaces the previous entry, with an untracked marker,
## so an older construction never resurfaces as "last".
func _undo_capture(token: String, region: String, action: String, label: String, before: Dictionary, builds_before: int) -> void:
	var hist:=_history(true)
	if hist.is_empty():return
	var last:Dictionary=hist.last
	var now:=_undo_utc()
	var ticks:=_undo_ticks()
	var serial:=int(hist.serial)
	if now<0.0 or ticks<0 or serial>=CONSTRUCTION_HISTORY.MAX_SERIAL:
		last.erase(token)
		return
	serial+=1
	hist.serial=serial
	# Never round creation into the future: an immediate summary must not see a
	# false clock rollback between the action and its next snapshot.
	var created:=floorf(now*1000.0)/1000.0
	var builds_delta:=int(state.players[token].get("builds",0))-builds_before
	var expected:int={"build":1,"remove":0,"move_object":0}.get(action,-1)
	# build_area and blueprint record a whole multi-piece transaction; each keeps
	# its own bound (25 vs MAX_BLUEPRINT_BUILDS) so neither widens the other.
	var multi_max:int={"build_area":CONSTRUCTION_HISTORY.MAX_AREA,"blueprint":CONSTRUCTION_HISTORY.MAX_BLUEPRINT_BUILDS}.get(action,0)
	var builds_ok:=(builds_delta>=1 and builds_delta<=multi_max) if multi_max>0 else builds_delta==expected
	if multi_max>0:label="%s ×%d"%[label,builds_delta]
	label=label.left(CONSTRUCTION_HISTORY.MAX_LABEL_LEN)
	var fallback_builds:=maxi(expected,1 if action=="build_area" else 0)
	if action=="blueprint":fallback_builds=clampi(builds_delta,1,multi_max)
	var entry:={"id":"c%d"%serial,"region":region,"action":action,"label":label,
		"created_utc":created,"expires_utc":created+CONSTRUCTION_HISTORY.WINDOW_SECONDS,
		"status":"invalid","reason":"untracked","builds":builds_delta if builds_ok else fallback_builds,
		"record":{},"watch":{}}
	if builds_ok:
		var source:Dictionary=before if region==REGIONS.HOME else before.regions.get(region,{})
		var prior:={}
		for field in CONSTRUCTION_HISTORY.TILE_LAYERS:
			var layer=source.get(field,{})
			prior[field]=layer if layer is Dictionary else {}
		var built:=_undo_record(prior,_layers_of(region),before.players,state.players,token)
		if built.ok:
			entry.record=built.record
			entry.watch=built.watch
			entry.status="live"
			entry.reason=""
			_undo_ticks_at[entry.id]=ticks
	last[token]=entry
	# Bounded persistence: drop closed entries first, then the oldest records.
	while last.size()>CONSTRUCTION_HISTORY.MAX_ENTRIES:
		var victim=null
		var victim_rank:=[2,0]
		for other in last:
			if other==token:continue
			var e=last[other]
			var rank:=[1 if (e is Dictionary and e.get("status")=="live") else 0,CONSTRUCTION_HISTORY.id_serial(e.get("id") if e is Dictionary else null)]
			if victim==null or rank[0]<victim_rank[0] or (rank[0]==victim_rank[0] and rank[1]<victim_rank[1]):
				victim=other
				victim_rank=rank
		if victim==null:break
		last.erase(victim)

## Undo record + dependency watch for one transaction between two region layer
## sets (TILE_LAYERS) and player tables. {ok, record, watch}; ok=false whenever
## the transaction cannot be tracked (too many changes / watch overflow...).
## Shared by _undo_capture and the blueprint quote's `undoable` preview.
static func _undo_record(prior: Dictionary, current: Dictionary, players_before: Dictionary, players_after: Dictionary, token: String) -> Dictionary:
	var b:={"ground":prior.ground,"objects":prior.objects,"roofs":prior.roofs,"players":players_before}
	var a:={"ground":current.ground,"objects":current.objects,"roofs":current.roofs,"players":players_after}
	var captured:=CONSTRUCTION_UNDO.capture(b,a,token,{"pending":0})
	if not captured.ok:return {"ok":false}
	var record:Dictionary=captured.record
	var watched:=CONSTRUCTION_HISTORY.build_watch(prior,current,record.changes)
	if not watched.ok:return {"ok":false}
	var revisions:={}
	for k in watched.watch:revisions[k]=0
	record.revisions=revisions
	if not CONSTRUCTION_UNDO.validate_record(record).ok:return {"ok":false}
	return {"ok":true,"record":record,"watch":watched.watch}

func _undo_no(message: String) -> Dictionary:
	return {"ok":false,"message":message,"left":0.0}

func _prune_undo_ticks() -> void:
	var keep:={}
	var history:=_history()
	if not history.is_empty():
		for entry in history.last.values():
			if entry is Dictionary and entry.get("status")=="live":keep[entry.id]=true
	for id in _undo_ticks_at.keys():
		if not keep.has(id):_undo_ticks_at.erase(id)

## Read-only full check of the actor's last record. MUST run oriented to the
## record's region. Returns {ok, message, entry, prepared, left}.
func _undo_check(token: String, id: String) -> Dictionary:
	var hist:=_history()
	var entry=null
	if not hist.is_empty():entry=hist.last.get(token)
	if not CONSTRUCTION_HISTORY.entry_basic(entry):return _undo_no(UNDO_MSG_MISSING if id!="" else CONSTRUCTION_HISTORY.TEXT_NONE)
	if id!="" and entry.id!=id:return _undo_no(UNDO_MSG_NOT_LAST)
	if entry.status!="live":return _undo_no(CONSTRUCTION_HISTORY.reason_text(entry.reason))
	if not state.players.has(token):return _undo_no("尚未加入世界")
	if player_region(token)!=entry.region:return _undo_no(UNDO_MSG_REGION)
	if _region!=entry.region:return _undo_no(CONSTRUCTION_UNDO.MSG_LAYERS)
	var timing:=_undo_time(entry)
	if not timing.ok:return _undo_no(CONSTRUCTION_HISTORY.reason_text(timing.code))
	var record:Dictionary=entry.record
	if not CONSTRUCTION_UNDO.validate_record(record).ok or record.get("actor")!=token:return _undo_no(CONSTRUCTION_UNDO.MSG_RECORD)
	var revisions:={}
	for k in record.revisions:
		if not entry.watch.has(k):return _undo_no(CONSTRUCTION_UNDO.MSG_RECORD)
		revisions[k]=0
	if revisions.size()!=entry.watch.size():return _undo_no(CONSTRUCTION_UNDO.MSG_RECORD)
	if not CONSTRUCTION_HISTORY.watch_matches(_layers_of(entry.region),entry.watch):return _undo_no(CONSTRUCTION_HISTORY.reason_text("changed"))
	var current:={"ground":state.ground,"objects":state.objects,"roofs":state.roofs,"players":state.players}
	var prepared:=CONSTRUCTION_UNDO.prepare(current,token,record,revisions)
	if not prepared.ok:return _undo_no(str(prepared.message))
	if int(state.players[token].get("builds",0))<int(entry.builds):return _undo_no(UNDO_MSG_STATS)
	var problem:=_undo_restore_problem(token,record.changes,prepared.layers)
	if problem!="":return _undo_no(problem)
	return {"ok":true,"message":CONSTRUCTION_HISTORY.TEXT_READY,"entry":entry,"prepared":prepared,"left":timing.left}

## "" when the staged inverse is placeable; read-only. Region oriented.
func _undo_restore_problem(token: String, changes: Dictionary, staged: Dictionary) -> String:
	var solid:={}
	var limited:={}
	var topology:Array[Vector2i]=[]
	var seen_topology:={}
	var kitchen:Array[Vector2i]=[]
	if _region==REGIONS.HOME:kitchen=PUBLIC_KITCHEN.site_cells(state)
	for layer in CONSTRUCTION_UNDO.LAYERS:
		var layer_changes:Dictionary=changes[layer]
		for tile in layer_changes:
			var parsed:=CONSTRUCTION_HISTORY.parse_tile(str(tile))
			if not parsed.ok:return CONSTRUCTION_UNDO.MSG_RECORD
			var c:Vector2i=parsed.cell
			# T042 defence in depth: never let an undo add/remove/replace a donated
			# object or the ground beneath it (registration already closed watchers).
			if layer!="roofs" and c in kitchen:return PUBLIC_KITCHEN.MSG_LOCKED
			var change:Dictionary=layer_changes[tile]
			if layer!="roofs" and not seen_topology.has(c):
				for side in ["before","after"]:
					var e=change[side]
					if e is Dictionary and str(e.get("type","")) in CONSTRUCTION_HISTORY.TOPOLOGY:
						seen_topology[c]=true
						topology.append(c)
						break
			var restored=change.before
			if restored==null:continue
			if not is_land(c) or water(c) or protected(c):return UNDO_MSG_TERRAIN
			var kind:=str(restored.get("type",""))
			if layer=="roofs":
				var below=staged.ground.get(tile)
				if not below is Dictionary or below.get("type")!="floor":return UNDO_MSG_ROOF
				if not is_auto_roof(restored) and below.get("owner")!=restored.get("owner"):return UNDO_MSG_ROOF
				continue
			if resource(c)!="" or state.crops.has(tile) or state.forest.has(tile):return UNDO_MSG_TERRAIN
			if layer!="objects":continue
			if kind in UNDO_SOLID or (kind=="door" and not restored.get("open",false)):solid[tile]=true
			if kind=="mine_drill" and (_region not in MINE_DRILL.REGIONS or int(state.mine_depths.unlocked)<5 or MINE_DRILL.placement(c)<0 or int(restored.get("dir",-1))!=MINE_DRILL.placement(c)):return UNDO_MSG_LOCKED
			if kind=="waterworks" and int(state.mine_depths.unlocked)<4:return UNDO_MSG_LOCKED
			if kind in KITCHEN_GATED and not kitchen_opened():return MILL_LOCKED_MSG
			# Beimen: only chests on chest-socket cells may ever come back.
			if _region==SALT_PAN.REGION and (kind not in SALT_BOXES or SALT_PAN.chest_socket_lot(c)<0):return SALT_PAN.REJECT_MESSAGE
			if kind=="water_pump" and not INDUSTRY.near_river(self,c):return UNDO_MSG_LOCKED
			limited["%s|%s"%[kind,str(restored.get("owner",""))]]=[kind,str(restored.get("owner",""))]
	# Per-owner limits on the staged layers (region-local like build; drills and
	# waterworks also world-wide; one drill per mine layer).
	var local_limits:={"sprinkler":SPRINKLER_LIMIT,"medium_sprinkler":SPRINKLER_LIMIT,"forester":FORESTRY.LIMIT,"conveyor":LOGISTICS.BELT_LIMIT}
	local_limits.merge(INDUSTRY.LIMITS)
	var staged_objects:Dictionary=staged.objects
	for pair in limited.values():
		var kind:String=pair[0]
		var owner:String=pair[1]
		var count:=0
		var any_drills:=0
		for obj in staged_objects.values():
			if obj.get("type")=="mine_drill":any_drills+=1
			if obj.get("type")==kind and obj.get("owner")==owner:count+=1
		if local_limits.has(kind) and count>int(local_limits[kind]):return UNDO_MSG_LIMIT
		if kind in ["waterworks","mine_drill"]:
			var total:=count
			for local in state.regions.values():
				for obj in local.objects.values():
					if obj.get("type")==kind and obj.get("owner")==owner:total+=1
			if total>(WATERWORKS.LIMIT if kind=="waterworks" else MINE_DRILL.LIMIT):return UNDO_MSG_LIMIT
		if kind=="mine_drill" and any_drills>1:return UNDO_MSG_LIMIT
	# Exact inverse must already be roof-consistent: no second reconcile on undo.
	if not topology.is_empty():
		if topology.size()>AUTO_ROOF_PLAN.MAX_TOUCHED:return UNDO_MSG_TOPOLOGY
		var plan:Dictionary=AUTO_ROOF_PLAN.reconcile({"ground":state.ground,"objects":state.objects,"roofs":state.roofs},staged,topology,token,BUILD.roof)
		if not plan.ok:return str(plan.message)
		if not plan.add.is_empty() or not plan.remove.is_empty():return UNDO_MSG_TOPOLOGY
	# Every active player in this region, the actor included.
	if not solid.is_empty():
		for active in regional_tokens():
			var who:Dictionary=state.players[active]
			for offset in UNDO_FOOT:
				var v:Vector2=Vector2(float(who.x),float(who.y))+offset
				if solid.has(key(Vector2i(floori(v.x),floori(v.y)))):return UNDO_MSG_OCCUPIED
	return ""

## Authoritative undo, oriented to the actor's region inside act(). act()
## restores the whole pre-action state on failure or save failure.
func _undo_apply(token: String, id: String) -> Dictionary:
	if id.is_empty() or id.length()>CONSTRUCTION_HISTORY.MAX_ID_LEN:return fail(UNDO_MSG_MISSING)
	var check:=_undo_check(token,id)
	if not check.ok:return fail(str(check.message))
	var entry:Dictionary=check.entry
	var record:Dictionary=entry.record
	var changes:Dictionary=record.changes
	for layer in CONSTRUCTION_UNDO.LAYERS:
		var target:Dictionary=state[layer]
		var layer_changes:Dictionary=changes[layer]
		for tile in layer_changes:
			var restored=layer_changes[tile].before
			if restored==null:target.erase(tile)
			else:target[tile]=(restored as Dictionary).duplicate(true)
	var inventories:Dictionary=check.prepared.inventories
	for owner in inventories:state.players[owner].inventory=inventories[owner]
	var player:Dictionary=state.players[token]
	player.builds=int(player.get("builds",0))-int(entry.builds)
	var others:=0
	for owner in record.inventory_deltas:
		if owner!=token:others+=1
	var label:=str(entry.label)
	_undo_close(entry,"consumed")
	var message:="已復原「%s」，材料已反向結算"%label
	if others>0:message+="；另有 %d 位原出資者的屋頂材料一併結算"%others
	return ok(message)

## Public, read-only summary for the actor's own last construction. Contains
## no tokens and no private record data. id "" when there is no record.
func undo_summary(token: String) -> Dictionary:
	var out:={"id":"","label":"","available":false,"reason":CONSTRUCTION_HISTORY.TEXT_NONE,"seconds_left":0.0,"region":""}
	var players=state.get("players")
	if not players is Dictionary or not players.has(token):return out
	var hist:=_history()
	if hist.is_empty():return out
	var entry=hist.last.get(token)
	if not CONSTRUCTION_HISTORY.entry_basic(entry) or not REGIONS.ALL.has(entry.region):return out
	out.id=str(entry.id)
	out.label=str(entry.label).left(CONSTRUCTION_HISTORY.MAX_LABEL_LEN)
	out.region=str(entry.region)
	if entry.status!="live":
		out.reason=CONSTRUCTION_HISTORY.reason_text(entry.reason)
		return out
	var timing:=_undo_time(entry)
	if not timing.ok:
		out.reason=CONSTRUCTION_HISTORY.reason_text(timing.code)
		return out
	out.seconds_left=float(timing.left)
	if player_region(token)!=entry.region:
		out.reason=UNDO_MSG_REGION
		return out
	var previous:=_region
	switch_region(entry.region)
	var check:=_undo_check(token,str(entry.id))
	switch_region(previous)
	out.available=bool(check.ok)
	out.reason=str(check.message)
	return out

func _apply(token: String, action: String, p: Vector2i, extra: String, build_style: String = "") -> Dictionary:
	var player: Dictionary=state.players[token]
	if action=="ferry_news_read":
		if not extra.is_valid_int() or int(extra)!=ISLAND_STORY_RECAP.marker(state):
			return fail("渡口近況有更新，請重新開啟島嶼近況。")
		player.ferry_recap_seen=int(extra)
		return ok("已記下這次查看的渡口近況。")
	if action=="news_read":
		if not extra.is_valid_int():return fail("近況資料有誤。")
		var mask:=int(extra)
		var completed:=island_project_mask()
		if mask<0 or mask>ISLAND_NOTES.project_mask() or (mask & completed)!=mask:return fail("請重新開啟島嶼近況。")
		player.news_seen=int(player.get("news_seen",0)) | mask
		return ok("已記下這次查看的島嶼近況。")
	if action=="news_note":
		var message:=ISLAND_NOTES.clean(extra)
		if message.is_empty():return fail("請輸入有效留言。")
		var notes:Array=state.get("island_notes",[])
		notes.push_front({"sender":str(player.name),"text":message,"time":float(state.time)})
		if notes.size()>ISLAND_NOTES.LIMIT:notes.pop_back()
		state.island_notes=notes
		return ok("留言已貼到島嶼近況。")
	var inv: Dictionary=player.inventory
	var k := key(p)
	var dist := Vector2(player.x,player.y).distance_to(Vector2(p)+Vector2(0.5,0.5))
	if action=="outlying_deliver":
		var commission:Dictionary=OUTLYING_COMMISSIONS.DEFS.get(extra,{})
		if not TRANSIT.boat_open(state):return fail("請先完成碼頭與小船工程。")
		if commission.get("region","")!=_region or p!=TRANSIT.STATIONS.get(_region,{}).get("cell") or dist>3.2:
			return fail("請到委託所在的接駁站交件。")
		var delivery:=OUTLYING_COMMISSIONS.complete(state,token,extra,{"apply":true,"auth":token})
		return ok(delivery.text) if delivery.ok else fail(delivery.text)
	if action=="dock_repair":
		if _region!=REGIONS.HOME or p!=Vector2i(40,29) or dist>3.2:return fail("請到渡口公告板交付造船材料。")
		if not CHAPTER_ONE.phase(state)=="complete" or not state.get("flower_nursery",{}).get("garden",{}).get("complete",false):
			return fail("先完成渡口與田尾的公共故事。")
		var stage:=int(state.get("dock_stage",0))
		if stage>=DOCK_REPAIRS.size():return fail("碼頭和小船都已修復。")
		if extra!=str(stage):return fail("工程進度有更新，請重新查看。")
		var cost:Dictionary=DOCK_REPAIRS[stage]
		for item in cost:
			if int(inv.get(item,0))<cost[item]:return fail("還需要 %s。"%NAMES[item])
		for item in cost:inv[item]-=cost[item]
		state.dock_stage=stage+1
		return ok("碼頭修好了，接著準備小船。" if stage==0 else "小船修好了，可以開始準備外島航行。")
	if action=="festival_story_open":
		if _region!=REGIONS.HOME or p!=Vector2i(40,29) or dist>3.2:return fail("請到渡口公告板籌備風鈴節。")
		var plan:=festival_story_view()
		if plan.opened:return fail("風鈴節已經開幕，可以重看回憶。")
		if not plan.boat_ready:return fail("先完成第四章的碼頭與小船工程。")
		if plan.projects!=ISLAND_NOTES.project_mask() or not plan.meal or plan.lights<2:
			return fail("請先完成六項工程、準備共餐，並在共餐桌周圍放兩盞燈。")
		state.festival_story_open=true
		return ok("風鈴節開幕了！大家沿著燈光回到渡口。")
	if action in ["travel","transit"]:
		var destination := extra
		var boat_arrival:=false
		var valid_point := p == REGIONS.exit_cell(_region)
		var allowed := destination == REGIONS.LANYANG if _region == REGIONS.HOME else (_region in [REGIONS.LANYANG,REGIONS.JINGUASHI] and destination == REGIONS.HOME)
		if action == "transit":
			allowed = false
			var station_id := TRANSIT.point_at(_region,p)
			valid_point = not station_id.is_empty()
			for option in TRANSIT.route_options(state,token,station_id):
				if option.region == destination:
					allowed=true
					boat_arrival=_region==REGIONS.HOME and option.mode==OUTLYING_COMMISSIONS.BOAT_MODE
			if not allowed:return fail("請先沿站點依序走訪，再使用轉乘捷徑。")
		if int(player.travel_epoch) >= 1000000000 or not state.picnic or not allowed or not valid_point or dist > 3.2:
			return fail("請完成渡口野餐，再靠近指定出口旅行。")
		var spawn := TRANSIT.arrival(_region,destination) if action == "transit" else REGIONS.spawn(destination)
		switch_region(destination)
		var arrival := safe_arrival(spawn)
		switch_region(player_region(token))
		if arrival == Vector2.ZERO:return fail("目的地出口附近沒有安全落點。")
		player.region = destination
		if boat_arrival:player.outlying_boat_arrival=true
		else:player.erase("outlying_boat_arrival")
		_record_exploration(player,destination)
		if TRANSIT.STATIONS.has(destination):player.travel_book.visited[destination]=true
		player.travel_epoch = int(player.travel_epoch) + 1
		player.x = arrival.x
		player.y = arrival.y
		for field in ["fishing","last_till","last_seed","last_harvest"]:player.erase(field)
		return ok("已抵達%s。" % REGIONS.label(destination))
	if action == "rescue":
		var point := safe_arrival(REGIONS.spawn(_region) if _region != REGIONS.HOME else SPAWN)
		if point == Vector2.ZERO:return fail("附近沒有安全落點。")
		player.x=point.x
		player.y=point.y
		return ok("已回到%s入口，背包物品都在" % REGIONS.label(_region))
	if action == "claim_milestone":
		if not Collections.MILESTONES.has(extra):
			return fail("找不到這項里程碑")
		var milestone: Dictionary = Collections.MILESTONES[extra]
		if player.collection.claimed.has(extra):
			return fail("這項里程碑的獎勵已領取")
		if Collections.progress(player, extra) < milestone.target:
			return fail("圖鑑進度還未達到「%s」" % milestone.name)
		if int(player.coins)>SHIPPING.MAX_COINS-int(milestone.coins):return fail(COIN_CAP_MSG)
		player.collection.claimed[extra] = true
		player.coins += milestone.coins
		for item in milestone.items:
			give(inv, item, milestone.items[item])
		return ok("已領取「%s」獎勵：%s" % [milestone.name, milestone.reward_text])
	if action in ["station_story","station_repair"]:
		if not STATION_LIFE.RESIDENTS.has(_region) or p!=STATION_LIFE.RESIDENTS[_region].cell or dist>3.2:return fail("請走到該站居民身旁。")
		return STATION_LIFE.apply(state,token,action,_region,extra)
	# T071 市集攤位：家園廣場的個人攤位，只寫本人的 player.market。
	if action in MARKET.ACTIONS:
		if not MARKET.unlocked(state):return fail(MARKET.LOCKED)
		if _region!=REGIONS.HOME:return fail(MARKET.WRONG_REGION)
		var stall:=MARKET.cell_for(state)
		if stall==MARKET.NO_CELL:return fail(MARKET.NO_STALL)
		if p!=stall:return fail(MARKET.WRONG_CELL)
		if dist>3.2:return fail(MARKET.TOO_FAR)
		return MARKET.apply(state,token,action,extra,NAMES)
	# T071 豐收接力：共用回合 state.harvest_relay；結算時才寫 player.harvest_relay。
	if action in HARVEST.ACTIONS:
		return HARVEST.apply(state,token,action,p,extra,_region==REGIONS.HOME,active_tokens)
	# T071 河岸釣魚會：共用回合 state.fish_meet；結算時才寫 player.fish_meet。
	if action in FISH_MEET.ACTIONS:
		return FISH_MEET.apply(state,token,action,p,extra,_region==REGIONS.HOME)
	# T071 家園布置題：共用回合 state.showcase；結算時才寫 player.showcase。
	if action in SHOWCASE.ACTIONS:
		return SHOWCASE.apply(state,token,action,p,extra,_region==REGIONS.HOME)
	# T071 紀念票兌換裝飾：只寫本人的 player.souvenir 與背包的兌換品 kit。
	if action in SOUVENIR.ACTIONS:
		return SOUVENIR.apply(state,token,action,p,extra,_region==REGIONS.HOME)
	# T067 共餐桌保溫底座（暖岩片）：一次性加裝寫 state.table_warmer；保溫上桌一輪六份。
	if action in TABLE_WARMER.ACTIONS:
		return TABLE_WARMER.apply(state,token,action,p,extra,_region==REGIONS.HOME)
	# 第 40 章茶陶上桌：茶陶組借給共餐桌（state.tea_service），一份焙茶泡六杯，每人每壺一杯。
	if action in TEA_SERVICE.ACTIONS:
		return TEA_SERVICE.apply(state,token,action,p,extra,_region==REGIONS.HOME)
	# 第 40 章蘭陽回訪「旱日分流」：共用 state.lanyang_revisit；領木牌只寫本人背包與 claimed。
	if action in LANYANG_REVISIT.ACTIONS:
		return LANYANG_REVISIT.apply(state,token,action,p,extra,_region==REGIONS.LANYANG)
	# 第 40 章金瓜石回訪「礦料調度」：共用 state.jinguashi_revisit；送出扣本人背包的礦料，
	# 領礦燈只寫本人背包與 claimed。
	if action in JINGUASHI_REVISIT.ACTIONS:
		return JINGUASHI_REVISIT.apply(state,token,action,p,extra,_region==REGIONS.JINGUASHI)
	# 第 40 章金瓜石初訪「河邊淘砂金」：只寫本人的 state.gold_panning.players[token] 與背包的含金礦料。
	if action in GOLD_PANNING.ACTIONS:
		return GOLD_PANNING.apply(state,token,action,p,extra,_region==REGIONS.JINGUASHI)
	# 第 40 章金瓜石初訪「運礦路線」：只寫本人的 state.ore_route.players[token] 與卸礦時的鈴幣。
	if action in ORE_ROUTE.ACTIONS:
		return ORE_ROUTE.apply(state,token,action,p,extra,_region==REGIONS.JINGUASHI)
	# 第 40 章貓空與鶯歌回訪「茶罐大單」：共用 state.tea_revisit；交罐／裝茶扣本人背包，
	# 領茶陶組只寫本人背包與 claimed。
	if action in TEA_REVISIT.ACTIONS:
		return TEA_REVISIT.apply(state,token,action,p,extra,_region)
	# 第 40 章臺南北門回訪「鹽籃批次」：共用 state.salt_revisit；入倉扣本人背包的海鹽、裝籃扣
	# 本人背包的纖維，領鹽籃只寫本人背包與 claimed。在北門的 _salt_allowed 拒絕之前轉入。
	if action in SALT_REVISIT.ACTIONS:
		return SALT_REVISIT.apply(state,token,action,p,extra,_region)
	# 第 40 章北門儲滷槽：共用 state.salt_brine（槽裡的桶數）；收滷／放滷只在本人裝了水車的鹽田區
	# 寫 pan.p／pan.t。step 已把鹽田推進到 state.time。在北門的 _salt_allowed 拒絕之前轉入。
	if action in SALT_BRINE.ACTIONS:
		return SALT_BRINE.apply(state,token,action,p,extra,_region)
	# 第 40 章風鈴節廣場地方記憶展：只寫本人的 player.memory_exhibit.seen（補看紀錄）。
	if action in MEMORY_EXHIBIT.ACTIONS:
		return MEMORY_EXHIBIT.apply(state,token,action,p,extra,_region==REGIONS.HOME)
	if _region in TRANSIT.LOCAL:return fail("公共站場只供步行與轉乘，請回農地或礦區作業。")
	var tea_farming:=_region==REGIONS.Bamboo.REGION and REGIONS.Bamboo.TEA_BEDS.has_point(p) and action in ["hoe","seed","water","harvest"]
	if _region in REGIONS.ANGLING_RESERVES and not tea_farming and action not in ["fish_start","fish_catch"] and action not in RESIDENT_BOND.ACTIONS and action not in RESIDENT_GOALS.ACTIONS: # T066：暖暖在暖泉高地，聊天送禮與一起做的事不是施工。
		return fail("保護區可以垂釣，施工請回家園。")
	if _region == FLOWER_NURSERY.REGION and action in FLOWER_REJECTED:return fail(FLOWER_REJECT_MSG)
	if _region == SALT_PAN.REGION and not _salt_allowed(action,p,extra):return fail(SALT_PAN.REJECT_MESSAGE)
	if dist>(5.0 if action=="build_area" and crafting_level(player)>=BATCH_BUILD_LEVEL else 3.2): return fail("靠近一點，才能和它互動")
	if action in COMMUNITY.ACTIONS:
		if _region!=REGIONS.HOME or not state.picnic or p==COMMUNITY.NO_CELL or p!=COMMUNITY.table_cell(state) or not extra.is_empty():
			return fail("請到風鈴渡口的共餐桌分食。")
		var dish:=action.get_slice("_",1)
		var item:String=COMMUNITY.DISHES[dish]
		var serving:=COMMUNITY.share_dish(state,token,action,dish,NAMES[item])
		if serving.ok and action.begins_with("claim_"):_record_discovery(player,"meals",item)
		return serving
	if action in ["fund_donate","fund_bridge"]:
		if _region!=REGIONS.HOME or p!=Vector2i(40,29):return fail("請到渡口公告板使用公共基金。")
		var fund:Dictionary=state.get("public_fund",{"balance":0,"contributors":{}})
		if action=="fund_donate":
			if extra not in FUND_DONATIONS:return fail("請選擇有效的捐款金額。")
			var amount:=int(extra)
			if int(player.coins)<amount:return fail("鈴幣不足。")
			var given:=int(fund.contributors.get(token,0))
			if given>1000000000-amount or int(fund.balance)>1000000000-amount:return fail("基金紀錄已達上限。")
			player.coins-=amount
			fund.balance=int(fund.balance)+amount
			fund.contributors[token]=given+amount
		else:
			if not extra.is_empty() or state.board:return fail("目前沒有待付款的渡口工程。")
			var cost:=bridge_fund_cost(state)
			if cost<=0 or int(fund.balance)<cost:return fail("公共基金不足，可繼續捐款或捐材料。")
			fund.balance=int(fund.balance)-cost
			state.donations={"wood":30,"stone":10}
			_finish_bridge()
		state.public_fund=fund
		return ok("謝謝你為渡口捐款。" if action=="fund_donate" else "公共基金已支付剩餘材料，河灣橋開通了！")
	if action in ["livestock_feed","livestock_collect","livestock_pet","livestock_install","livestock_empty","livestock_pen"]:
		if _region!=REGIONS.HOME or not state.picnic or not LIVESTOCK.ANIMALS.has(extra) or p!=LIVESTOCK.ANIMALS[extra].cell or dist>3.2:
			return fail("完成渡口野餐後，可到牧場照料牛羊。")
		if action=="livestock_install" and not state.get("flower_nursery",{}).get("garden",{}).get("complete",false):
			return fail("完成田尾公共花園後解鎖畜牧收集器。")
		if action=="livestock_pen" and not LIVESTOCK.pen_status(state.objects,extra):
			return fail("請先圍好圈舍並留一扇木門。")
		return LIVESTOCK.perform(state.livestock,inv,extra,action,float(state.time))
	# T042 public kitchen: HOME only, after the normal 3.2 reach gate (p = stove).
	if action in PUBLIC_KITCHEN.ACTIONS:
		if _region!=REGIONS.HOME:return fail("請回到風鈴渡口使用公共廚房。")
		return PUBLIC_KITCHEN.perform(self,token,action,p,extra)
	# T036 explicit material sources. Plain recipe IDs never contain '|', so the
	# backpack-only actions below stay unchanged; perform() re-enters _apply
	# with the canonical action and the plain recipe ID (no recursion loop).
	if action==MATERIAL_SOURCES.PREPARE_ACTION:return MATERIAL_SOURCES.prepare(self,token,p,extra)
	# Salt kit gate on the sourced path too (explained before any material quote).
	if action=="craft" and extra.contains("|"):
		var sourced_recipe:String=extra.split("|")[0]
		if sourced_recipe in SALT_GATED and not SALT_PAN.craft_allowed(state,token,sourced_recipe):return fail(SALT_PAN.CRAFT_LOCKED_MESSAGE)
		if sourced_recipe==INDUSTRY.GATE_KIT and not LANYANG_REVISIT.tech_unlocked(state):return fail(INDUSTRY.GATE_LOCKED)
		if sourced_recipe==INDUSTRY.TOWER_KIT and not LANYANG_REVISIT.tech_unlocked(state):return fail(INDUSTRY.TOWER_LOCKED)
	if action in MATERIAL_SOURCES.ACTIONS and extra.contains("|"):return MATERIAL_SOURCES.perform(self,token,action,p,extra)
	if TEA_CERAMICS.SITES.has(action):
		if CHAPTER_ONE.phase(state)!="complete":return fail("先完成渡口的第一章故事。")
		return TEA_CERAMICS.apply(state,token,action,_region,p,extra)
	# Chapter 3 Tianwei nursery stations (after the normal 3.2 reach gate).
	if action in FLOWER_NURSERY.ACTIONS:
		if not FLOWER_NURSERY.unlocked(state,token):return fail(FLOWER_LOCKED_MSG)
		return FLOWER_NURSERY.apply(state,token,action,_region,p,extra)
	# Chapter 4 Beimen salt pans (after the normal 3.2 reach gate).
	if action in SALT_PAN.ACTIONS:return _salt_action(token,action,p,extra)
	if action in MINE_SURVEY.ACTIONS:
		if not extra.is_empty():return fail("請重新選擇踏查操作。")
		if action=="survey_claim":
			if _region!=REGIONS.JINGUASHI or p!=bobo_sites().table:return fail("請回金瓜石波波的整理桌。")
			return MINE_SURVEY.claim(state,token)
		var depth:=MINES.IDS.find(_region)+1
		if depth<=0 or p!=MINE_SURVEY.POINTS[depth]:return fail("請靠近本層側洞的觀察點。")
		return MINE_SURVEY.observe(state,token,depth)
	if action in BOBO_WORKSHOP.ACTIONS:
		if _region != REGIONS.JINGUASHI or p != bobo_sites().table:return fail("請到金瓜石波波的整理桌。")
		return BOBO_WORKSHOP.apply(state,token,action,extra)
	if action in MINE_AUTO_FREIGHT.ACTIONS:
		if _region not in MINE_AUTO_FREIGHT.REGIONS or p!=MINES.SERVICE or int(state.mine_depths.unlocked)<5:return fail("請先修好第四層軌道，再到礦務站設定自動裝運。")
		return MINE_AUTO_FREIGHT.apply(state,token,action,extra,_region,state.objects,state.regions[_region].objects)
	if action in MINE_FREIGHT.ACTIONS:
		var home_objects: Dictionary = state.objects if _region == REGIONS.HOME else state.regions[_region].objects
		return MINE_FREIGHT.apply(state,token,action,p,extra,_region,home_objects)
	if action in ["mine_travel","mine_rest","mine_commission","mine_extract",HOIST_ACTION] or (_region in MINES.IDS and action=="pick" and p in MINES.NODES):
		return mine_action(token,action,p,extra,inv)
	if action in HISTORY_MEMORY.ACTIONS:
		if _region != REGIONS.LANYANG:return fail("請先到蘭陽試作田。")
		return HISTORY_MEMORY.apply(state,token,action,p,extra)
	if action=="greenhouse_report":
		if _region!=REGIONS.LANYANG or p!=LANYANG_LIFE.SERVICE:return fail("請到宜蘭水圳找星禾。")
		if player.get("greenhouse_reported",false):return fail("星禾已經把你的收成寫進手記了。")
		if not player.get("greenhouse_glass_crafted",false) or not CROPS.has(player.get("greenhouse_cross_season_crop","")):
			return fail("先製作玻璃，並從自己的溫室收成一株跨季作物。")
		var report_bond_before:=RESIDENT_BOND.stage(player,"xinghe")
		player.greenhouse_reported=true
		var report_bond_note:=RESIDENT_BOND.stage_up_text("xinghe",report_bond_before,RESIDENT_BOND.stage(player,"xinghe"))
		return ok("星禾把你的跨季收成寫進了水圳手記，並送你溫室花架圖樣。"+("" if report_bond_note.is_empty() else " "+report_bond_note))
	if action in LANYANG_LIFE.ACTIONS:return lanyang_action(token,action,p,inv)
	if action=="borrow_mine_pick":
		if _region!=REGIONS.HOME or p!=COPPER_CELL:return fail("請到渡口運入礦料點借用公用鎬。")
		if not state.picnic:return fail("渡口野餐後才開放公用鎬。")
		if player.get("borrowed_mine_pick",false):return fail("你已有公用鎬使用資格。")
		player.borrowed_mine_pick=true
		return ok("取得公用鎬使用資格。可在渡口練習礦料點與金瓜石淺礦場採銅。")
	if _region == REGIONS.JINGUASHI and (action == "mine_copper" or (action == "pick" and p in JINGUASHI.NODES)):
		if p not in JINGUASHI.NODES:return fail("請到合作礦場的礦料點。")
		if int(inv.get("reinforced_pick",0))<1 and not player.get("borrowed_mine_pick",false):return fail("先製作強化鎬，或到渡口借用公用鎬。")
		var ready: Dictionary = state.jinguashi.ready
		if float(ready.get(k,0.0)) > float(state.time):return fail("這個礦點正在整理，請稍候。")
		if int(inv.get("copper_ore",0)) > 1000000000 - JINGUASHI.YIELD:return fail("背包中的銅礦料已達上限。")
		give(inv,"copper_ore",JINGUASHI.YIELD)
		ready[k] = float(state.time) + JINGUASHI.COOLDOWN
		return ok("取得合作礦場銅礦料 +%d。" % JINGUASHI.YIELD)
	if _region != REGIONS.HOME and action in ["chapter_starter","ship","order","order_accept","order_cancel","buy","sell","picnic","donate","pet","feed","egg","festival_start","festival_collect","quarry","mine_copper"]:
		return fail("請回到風鈴渡口使用這項功能。")
	if action == "chapter_starter":
		if p != CHAPTER_ONE.STARTER_CELL or not state.chapter_one.shipped or not state.board:
			return fail("先出貨並修好渡口，再找阿榆換供水組。")
		if state.chapter_one.starter_claims.has(token):
			return fail("你已向阿榆換過供水組。")
		for item in CHAPTER_ONE.STARTER_COST:
			if int(inv.get(item, 0)) < CHAPTER_ONE.STARTER_COST[item]:
				return fail("需要木材 12、石材 8、纖維 4。")
		for item in CHAPTER_ONE.STARTER_ITEMS:
			if int(inv.get(item, 0)) > CHAPTER_ONE.MAX_TRACKED - CHAPTER_ONE.STARTER_ITEMS[item]:
				return fail("背包中的物品已達上限。")
		for item in CHAPTER_ONE.STARTER_COST:
			inv[item] -= CHAPTER_ONE.STARTER_COST[item]
		for item in CHAPTER_ONE.STARTER_ITEMS:
			give(inv, item, CHAPTER_ONE.STARTER_ITEMS[item])
		state.chapter_one.starter_claims[token] = true
		return ok("阿榆修好了灑水器、兩段水管和水桶。")
	if action == "ship":
		if p == SHIPPING.NO_CELL or p != SHIPPING.cell_for(state):
			return fail("出貨箱目前無法使用。")
		var sale := SHIPPING.verify(extra, inv, SHIPPING.prices(CROPS, FISH, OTHER_SALES), int(player.coins))
		if not sale.ok:
			return sale
		for item in sale.quantities:
			inv[item] -= sale.quantities[item]
		player.coins += sale.total
		var already_shipped: bool=state.chapter_one.shipped
		CHAPTER_ONE.record_shipment(state,token,sale.quantities)
		if state.chapter_one.shipped and not already_shipped:
			note_resident_participation(token,"shipment")
		var result := ok("出貨完成，獲得 %d 鈴幣。" % sale.total)
		result.total = sale.total
		return result
	if action=="harvest_area":
		if int(inv.get("harvester",0))<1:return fail("先在工作台製作手推收割機")
		if int(inv.get("charcoal",0))<1:return fail("收割機需要木炭，作物沒有被採收")
		if float(state.time)-float(player.get("last_harvest",{}).get("at",-10))<HARVESTER.COOLDOWN:return fail("收割機正在收起割刀，稍候再試")
		var plan:Dictionary=HARVESTER.plan(self,token,p)
		if plan.cells.is_empty():return fail("範圍內沒有可採收的成熟作物，未消耗木炭")
		for kind in plan.yields:
			if int(inv.get(kind,0))+int(plan.yields[kind])>1000000000:return fail("收成物品已達上限，請先整理背包")
		if int(player.harvests)+plan.cells.size()>1000000000:return fail("採收紀錄已達上限，這次沒有施工")
		var report:PackedStringArray=[]
		for kind in plan.yields:report.append("%s +%d"%[NAMES[kind],plan.yields[kind]])
		for target_key in plan.cells:_harvest_plot(token,player,state.crops[target_key],target_key)
		give(inv,"charcoal",-1)
		player.last_harvest={"at":float(state.time),"x":p.x,"y":p.y,"cells":plan.cells.duplicate()}
		return ok("收割 %d 格 · %s · 木炭 −1"%[plan.cells.size(),"、".join(report)])
	if action=="seed_area":
		if int(inv.get("seeder",0))<1:return fail("先在工作台製作手推播種機")
		if not CROPS.has(extra):return fail("請先選擇作物種子")
		if int(inv.get(extra+"_seed",0))<1:return fail("這種種子用完了，按 C 換種子或到攤位購買")
		if int(inv.get("charcoal",0))<1:return fail("播種機需要木炭，這次沒有消耗種子")
		if float(state.time)-float(player.get("last_seed",{}).get("at",-10))<SEEDER.COOLDOWN:return fail("播種機正在收起料斗，稍候再試")
		var plan:Dictionary=SEEDER.plan(self,token,p,extra)
		if plan.cells.is_empty():return fail("範圍內沒有自己的空農田，未消耗種子或木炭")
		for target_key in plan.cells:
			var plot:Dictionary=state.crops[target_key]
			plot.kind=extra
			plot.growth=0.0
			plot["remaining"]=int(CROPS[extra].get("cycles",1))
		give(inv,extra+"_seed",-plan.cells.size())
		give(inv,"charcoal",-1)
		player.last_seed={"at":float(state.time),"x":p.x,"y":p.y,"cells":plan.cells.duplicate(),"kind":extra}
		return ok("播下%s %d 格 · 種子 −%d · 木炭 −1，記得供水"%[CROPS[extra].name,plan.cells.size(),plan.cells.size()])
	if action=="till_area":
		if int(inv.get("tiller",0))<1:return fail("先在工作台製作手推耕田機")
		if int(inv.get("charcoal",0))<1:return fail("耕田機需要木炭，這次沒有施工")
		if float(state.time)-float(player.get("last_till",{}).get("at",-10))<TILLER.COOLDOWN:return fail("耕田機正在收起滾輪，稍候再試")
		var plan:Dictionary=TILLER.plan(self,token,p)
		if plan.cells.is_empty():return fail("範圍內沒有可整地的空地，未消耗木炭")
		for target_key in plan.cells:
			state.crops[target_key]={"kind":"","growth":0.0,"wet":false,"owner":token}
		give(inv,"charcoal",-1)
		player.last_till={"at":float(state.time),"x":p.x,"y":p.y,"cells":plan.cells.duplicate()}
		return ok("已整地 %d 格 · 木炭 −1，接著選種子播種"%plan.cells.size())
	if action in MINE_DRILL.ACTIONS:
		var drill:Dictionary=state.objects.get(k,{})
		if _region not in MINES.IDS or drill.get("type")!="mine_drill" or drill.get("owner")!=token:return fail("只能操作自己在礦層的採掘機。")
		return MINE_DRILL.operate(drill,inv,action,extra)
	if action in WATERWORKS.ACTIONS:
		var device:Dictionary=state.objects.get(k,{})
		if device.get("type")!="waterworks" or device.get("owner")!=token:return fail("只能操作自己的水力加工台。")
		return WATERWORKS.operate(device,inv,action,extra)
	if action=="craft":
		if extra=="supply_box_kit" and exploration_level(exploration_points(player))<SUPPLY_BOX_LEVEL:return fail("探索達到六級後可製作便攜補給箱。")
		if extra=="mine_drill_kit" and int(state.mine_depths.unlocked)<5:return fail("先完成第四層礦道工程。")
		if extra=="waterworks_kit" and int(state.mine_depths.unlocked)<4:return fail("先完成礦場第三層的抽水工程。")
		if extra == "gold_sample" and _region != REGIONS.HOME:return fail("請把含金礦料帶回渡口工作台。")
		if extra in KITCHEN_GATED and not kitchen_opened():return fail(MILL_LOCKED_MSG)
		if extra in SALT_GATED and not SALT_PAN.craft_allowed(state,token,extra):return fail(SALT_PAN.CRAFT_LOCKED_MESSAGE)
		if extra==INDUSTRY.GATE_KIT and not LANYANG_REVISIT.tech_unlocked(state):return fail(INDUSTRY.GATE_LOCKED)
		if extra==INDUSTRY.TOWER_KIT and not LANYANG_REVISIT.tech_unlocked(state):return fail(INDUSTRY.TOWER_LOCKED)
		if state.objects.get(k,{}).get("type","")!="bench" or not CRAFT.has(extra):return fail("到工作台旁選擇配方")
		if extra=="reinforced_pick" and (player.get("crafted_reinforced_pick",false) or int(inv.get(extra,0))>0):return fail("你已有強化石鎬或已製作過；若已收進箱子，請取回原鎬")
		var recipe:Dictionary=CRAFT[extra]
		if int(inv.get(extra,0))+int(recipe.yield)>1000000000:return fail("背包中的物品已達上限")
		for item in recipe.ingredients:
			if int(inv.get(item,0))<int(recipe.ingredients[item]):return fail("製作材料不足")
		for item in recipe.ingredients:give(inv,item,-int(recipe.ingredients[item]))
		give(inv,extra,int(recipe.yield))
		if extra=="reinforced_pick":player.crafted_reinforced_pick=true
		if extra=="glass":player.greenhouse_glass_crafted=true
		player.crafting_points=mini(1000000000,int(player.get("crafting_points",0))+1)
		return ok("製作完成："+recipe.name)
	if action=="mine_copper" or (action=="pick" and _region==REGIONS.HOME and p==COPPER_CELL):
		if p!=COPPER_CELL:return fail("請到渡口的運入練習礦料點採集")
		if int(inv.get("reinforced_pick",0))<1 and not player.get("borrowed_mine_pick",false):return fail("需要強化石鎬或公用鎬才能採銅")
		if float(state.copper.ready)>float(state.time):return fail("運入練習礦料正在補充")
		state.copper.ready=float(state.time)+12.0
		give(inv,"copper_ore",2)
		return ok("採到銅礦 ×2")
	if action in ["configure_conveyor","toggle_conveyor","unload_conveyor","toggle_auto_processing","feed_processing","unload_processing_input","collect_processing_output"]:
		return operate_logistics(token,k,action,extra)
	if action in ["toggle_forester","load_forester","unload_forester","collect_forester"]:
		return operate_forester(token,k,action,extra)
	if action in ["refill_tank","toggle_pump"]:
		var device:Dictionary=state.objects.get(k,{})
		var required:="water_tank" if action=="refill_tank" else "water_pump"
		if device.get("type","")!=required or device.owner!=token:return fail("只能操作自己的設備")
		if action=="refill_tank":
			device.water=INDUSTRY.TANK_CAPACITY
			return ok("儲水桶已補滿")
		if not device.enabled and not INDUSTRY.near_river(self,p):return fail("水泵附近需要河水")
		device.enabled=not device.enabled
		return ok("河水泵已啟用" if device.enabled else "河水泵已停用")
	# 第 40 章分流閘：只有主人能切換 open/low/closed（同 toggle_pump 的權限）。
	if action==INDUSTRY.GATE_ACTION:
		var gate:Dictionary=state.objects.get(k,{})
		if gate.get("type","")!=INDUSTRY.GATE_KIND or gate.get("owner","")!=token:return fail(INDUSTRY.GATE_NOT_OWNER)
		if extra not in INDUSTRY.GATE_MODES:return fail(INDUSTRY.GATE_BAD_MODE)
		if str(gate.get("mode","open"))==extra:return fail(INDUSTRY.GATE_SAME_MODE)
		gate.mode=extra
		return ok("分流閘已設為「%s」"%INDUSTRY.gate_mode_name(extra))
	# 第 40 章水塔：只有主人能切換 出水／只蓄水（extra 不使用）。
	if action==INDUSTRY.TOWER_ACTION:
		var tower:Dictionary=state.objects.get(k,{})
		if tower.get("type","")!=INDUSTRY.TOWER_KIND or tower.get("owner","")!=token:return fail(INDUSTRY.TOWER_NOT_OWNER)
		tower.enabled=tower.get("enabled",false)!=true
		return ok("水塔已設為「%s」"%INDUSTRY.tower_enabled_name(tower.enabled))
	# 第 40 章定量配水：桶水保留量與每日配水（extra＝"reserve:<n>"／"quota:<n>"），只有主人。
	if action==INDUSTRY.TOWER_SET_ACTION:
		var set_tower:Dictionary=state.objects.get(k,{})
		if set_tower.get("type","")!=INDUSTRY.TOWER_KIND or set_tower.get("owner","")!=token:return fail(INDUSTRY.TOWER_NOT_OWNER)
		var set_problem:String=INDUSTRY.tower_set_apply(set_tower,str(extra),INDUSTRY.tower_day(float(state.time)))
		if set_problem!="":return fail(set_problem)
		return ok(INDUSTRY.tower_set_message(str(extra)))
	if action in ["start_processing","claim_processing","cancel_processing","queue_processing","cancel_processing_job"]:
		return process_industry(token,k,action,extra)
	if action in ["refill_sprinkler","toggle_sprinkler"]:
		var device:Dictionary=state.objects.get(k,{})
		if not INDUSTRY.SPRINKLER_CAPACITIES.has(device.get("type","")) or device.owner!=token:return fail("只能操作自己的灑水器")
		if action=="refill_sprinkler":
			device.water=INDUSTRY.SPRINKLER_CAPACITIES[device.type]
			return ok("灑水器已補滿")
		device.enabled=not device.enabled
		return ok("灑水器已啟用" if device.enabled else "灑水器已停用")
	if action=="festival_start":
		if p!=Vector2i(40,29) or not state.picnic:return fail("先完成渡口野餐，再到公告板開始風鈴接力")
		var f:Dictionary=state.festival
		if f.active:return fail("風鈴接力已經開始，跟朋友一起去找金色風鈴吧")
		if float(state.time)<float(f.ready):return fail("風鈴正在休息，約 %d 秒後能再玩"%ceili(float(f.ready)-float(state.time)))
		if extra!=str(int(f.round)):return fail("活動已更新，請重新打開活動面板")
		state.festival={"round":int(f.round)+1,"active":true,"collected":0,"contributors":{},"started":float(state.time),"finished":0.0,"ready":0.0,"best":float(f.best)}
		return ok("風鈴接力開始！跟著金色風鈴靠近按 E，共同收集 12 次。沒有失敗倒數。")
	if action=="festival_collect":
		var f:Dictionary=state.festival
		if not f.active or extra!=Festival.ticket(f):return fail("這枚風鈴已被接走，找下一個金色風鈴吧")
		if p!=Festival.target(f) or dist>1.6:return fail("走到金色風鈴身邊，再按 E 接住")
		f.contributors[token]=int(f.contributors.get(token,0))+1
		f.collected+=1
		if int(f.collected)<Festival.GOAL:return ok("風鈴 +1！大家一起完成了 %d / 12，下一枚換位置了"%int(f.collected))
		f.active=false;f.finished=float(state.time);f.ready=float(state.time)+Festival.COOLDOWN
		var elapsed:=maxf(0.001,float(state.time)-float(f.started))
		f.best=elapsed if float(f.best)<=0 else minf(float(f.best),elapsed)
		for who in f.contributors:
			# T093: 活動是大家共用的，不能因為一個人的錢包滿了就失敗；超過上限的部分不發。
			state.players[who].coins=mini(SHIPPING.MAX_COINS,int(state.players[who].coins)+20+2*int(f.contributors[who]))
		return ok("十二枚風鈴連成一首歌！參與者各得 20 鈴幣＋每枚 2 鈴幣，G 查看成果。")
	if action=="build_area":
		var parts:=extra.split("|")
		if parts.size()!=3 or parts[0] not in ["floor","path","roof"] or not parts[1].is_valid_int() or not parts[2].is_valid_int():return fail("請重新選擇施工範圍")
		var end:=Vector2i(int(parts[1]),int(parts[2]))
		var a:=Vector2i(mini(p.x,end.x),mini(p.y,end.y))
		var b:=Vector2i(maxi(p.x,end.x),maxi(p.y,end.y))
		var count:=(b.x-a.x+1)*(b.y-a.y+1)
		var area_limit:=build_area_limit(player)
		if abs(end.x)>1000 or abs(end.y)>1000 or count>area_limit or count<1:return fail("一次最多施工 %d 格"%area_limit)
		var reach:=5.0 if area_limit>BASIC_BUILD_AREA else 3.2
		var kind:String=parts[0]
		var keys:Array[String]=[]
		for y in range(a.y,b.y+1):
			for x in range(a.x,b.x+1):
				var tile:=Vector2i(x,y);var tile_key:=key(tile)
				if Vector2(player.x,player.y).distance_to(Vector2(tile)+Vector2(0.5,0.5))>reach:return fail("整個施工範圍需在可施工距離內")
				if water(tile) or protected(tile):return fail("範圍包含水域或公共通道，這次沒有扣料")
				if kind=="roof":
					if state.roofs.has(tile_key) or not state.ground.has(tile_key) or state.ground[tile_key].type!="floor" or state.ground[tile_key].owner!=token:return fail("整片屋頂都需要自己的木地板，且不能重疊屋頂")
				elif resource(tile)!="" or state.crops.has(tile_key) or state.objects.has(tile_key) or state.ground.has(tile_key):return fail("範圍裡有東西，這次沒有放置或扣料")
				keys.append(tile_key)
		for item in ["wood","stone","fiber"]:
			if int(inv.get(item,0))<int(BUILD[kind].get(item,0))*count:return fail("整片施工的"+NAMES[item]+"不足")
		for item in ["wood","stone","fiber"]:inv[item]=int(inv.get(item,0))-int(BUILD[kind].get(item,0))*count
		var layer:Dictionary=state.roofs if kind=="roof" else state.ground
		for tile_key in keys:
			var piece := {"type":kind,"owner":token,"items":{}}
			if not build_style.is_empty():piece.style=build_style
			layer[tile_key]=piece
		player.builds+=count
		return ok("一次放好了 %d 格%s，材料已保存扣除"%[count,BUILD[kind].name])
	if action=="move_object":
		var coordinates:=extra.split(",")
		if coordinates.size()!=2 or not coordinates[0].is_valid_int() or not coordinates[1].is_valid_int():return fail("請重新選擇搬移位置")
		var destination:=Vector2i(int(coordinates[0]),int(coordinates[1]))
		var to_key:=key(destination)
		if _region==REGIONS.HOME and PUBLIC_KITCHEN.is_site_cell(state,p):return fail(PUBLIC_KITCHEN.MSG_LOCKED)
		var obj:Dictionary=state.objects.get(k,{})
		var permission:=PLOT_PERMISSIONS.can_dismantle(self,token,p,true)
		if not permission.ok:return fail(permission.message)
		if obj.type in ["wall","window","door"]:return fail("牆門窗請拆除後重新建造，材料會退回")
		if obj.type=="conveyor" and (obj.enabled or not obj.items.is_empty()):return fail("請停用並清空輸送帶")
		if obj.type=="mine_drill" and not MINE_DRILL.can_move(obj):return fail("請停用並清空採掘機。")
		if obj.type=="waterworks" and not WATERWORKS.can_move(obj):return fail("請停用並清空水力加工台。")
		if (obj.type in LOGISTICS.PROCESSORS or obj.type in ["seed_maker","loom","glass_furnace"]) and not LOGISTICS.processing_idle(obj):return fail(PROCESSING_MSG_BUSY)
		if obj.type in LOGISTICS.PROCESSORS and not LOGISTICS.processor_ready_to_move(obj):return fail("請停用自動加工並清空設備")
		if obj.type=="forester" and not FORESTRY.can_move(obj):return fail("請先停用林務站並取回全部材料")
		if obj.has("job"):return fail("先領取或取消目前工作，再搬動")
		if obj.has("cooking") and not cooking_idle(obj):return fail(COOKING_MSG_BUSY)
		if obj.type=="mine_drill" and MINE_DRILL.placement(destination)<0:return fail("採掘機必須正對本層指定礦點。")
		if destination==p:return fail("這就是原本的位置")
		if Vector2(player.x,player.y).distance_to(Vector2(destination)+Vector2(0.5,0.5))>3.2:return fail("新位置也要在身邊三格內")
		if obj.type=="water_pump" and not INDUSTRY.near_river(self,destination):return fail("水泵需放在河水兩格內的陸地")
		if water(destination) or protected(destination) or resource(destination)!="" or state.objects.has(to_key) or state.crops.has(to_key):return fail("新位置不是可用空地，家具仍留在原處")
		if obj.type not in ["chair","lamp","sign","water_pipe","conveyor","diversion_gate"]:
			for active_token in regional_tokens():
				var who:Dictionary=state.players[active_token]
				if Vector2(who.x,who.y).distance_to(Vector2(destination)+Vector2(0.5,0.5))<0.8:return fail("這裡有人，等他移開再搬")
		if obj.type=="mine_drill":obj.dir=MINE_DRILL.placement(destination)
		state.objects[to_key]=obj
		state.objects.erase(k)
		return ok("搬好了！家具與箱內物品一起保存，沒有額外扣料")
	# T066 好感：每日聊天與送禮，只寫本人的 player.bonds。
	if action in RESIDENT_BOND.ACTIONS:
		var bond_parts:=extra.split(":")
		var bond_resident:=str(bond_parts[0]) if bond_parts.size()>0 else ""
		if bond_resident not in RESIDENT_BOND.RESIDENTS:return fail("請走到這位居民身邊。")
		var bond_spot:=bond_place(state,bond_resident)
		if str(bond_spot[0])!=_region or p!=bond_spot[1]:return fail("請走到這位居民身邊。")
		var bond_locked:=RESIDENT_BOND.locked_reason(state,bond_resident)
		if not bond_locked.is_empty():return fail(bond_locked)
		Village.ensure_player(player)
		return RESIDENT_BOND.apply(player,inv,action,bond_parts,float(state.time),NAMES)
	# T066「一起做的事」：好感到了那一階，在居民身邊完成設定集的行動；只寫本人的 player.bond_goals。
	# 第三批：CLAIM_ACTION 在同一個站位補領紀念小物（extra＝"居民:階數"）。
	if action in RESIDENT_GOALS.ACTIONS:
		var goal_parts:=extra.split(":")
		var goal_resident:=str(goal_parts[0]) if goal_parts.size()>0 else ""
		if goal_resident not in RESIDENT_BOND.RESIDENTS:return fail("請走到這位居民身邊。")
		var goal_spot:=bond_place(state,goal_resident)
		if str(goal_spot[0])!=_region or p!=goal_spot[1]:return fail("請走到這位居民身邊。")
		var goal_locked:=RESIDENT_BOND.locked_reason(state,goal_resident)
		if not goal_locked.is_empty():return fail(goal_locked)
		Village.ensure_player(player)
		if action==RESIDENT_GOALS.CLAIM_ACTION:return RESIDENT_GOALS.claim(player,inv,goal_parts)
		return RESIDENT_GOALS.apply(player,inv,goal_parts,NAMES,state,token)
	if action=="quest":
		var parts:=extra.split(":")
		if parts.size()!=2 or not parts[1].is_valid_int():return fail("請重新打開居民委託")
		extra=parts[0]
		if not Village.NPCS.has(extra) or Village.npc_region(extra)!=_region:return fail("請到對應居民身邊交件")
		if p!=Village.resident_cell(state,extra):return fail("請到對應居民身邊交件")
		Village.ensure_player(player)
		var stage:=int(player.stories[extra])
		if int(parts[1])!=stage:return fail("委託已更新，請重新和居民交談")
		if stage>=Village.QUESTS[extra].size():return fail("這位居民的故事已經完成，可以在 J 手冊重看")
		var quest:Dictionary=Village.QUESTS[extra][stage]
		var reason:=Village.blocked_reason(state,player,token,quest)
		if not reason.is_empty():return fail(reason)
		for item in quest.items:
			if int(inv.get(item,0))<int(quest.items[item]):return fail("還需要 %s %d"%[NAMES[item],int(quest.items[item])-int(inv.get(item,0))])
		if int(player.coins)>1000000000-int(quest.coins):return fail("鈴幣已達上限。")
		for item in quest.reward:
			if int(inv.get(item,0))-int(quest.items.get(item,0))>1000000000-int(quest.reward[item]):return fail("背包已達上限。")
		for item in quest.items:inv[item]-=int(quest.items[item])
		player.coins+=int(quest.coins)
		for item in quest.reward:give(inv,item,int(quest.reward[item]))
		var bond_before:=RESIDENT_BOND.stage(player,extra)
		player.stories[extra]=stage+1
		var bond_note:=RESIDENT_BOND.stage_up_text(extra,bond_before,RESIDENT_BOND.stage(player,extra))
		return ok("%s：%s（鈴幣 +%d，J 可重看）%s"%[Village.NPCS[extra].name,quest.line,quest.coins,"" if bond_note.is_empty() else " "+bond_note])
	if action in ["order","order_accept","order_cancel"]:
		if _region!=REGIONS.HOME or p!=Vector2i(40,29) or not state.board:return fail("修好公告板後即可接生活訂單")
		var now:=float(state.time)
		var context:=ORDER_CATALOG.context_from_world(self,token)
		var book:Dictionary=player.get("orders",{})
		var result:Dictionary
		match action:
			"order_accept":result=ORDER_CATALOG.accept(book,extra,now,context)
			"order_cancel":result=ORDER_CATALOG.cancel(book,extra,now)
			_:result=ORDER_CATALOG.check_delivery(book,extra,now,inv,context)
		if not result.ok:
			var missing:=str(result.get("missing_item",""))
			return fail(str(result.message)+str(NAMES.get(missing,missing)))
		if action=="order":
			if int(player.coins)>1000000000-int(result.order.coins):return fail("鈴幣已達上限")
			for item in result.order.items:inv[item]-=int(result.order.items[item])
			player.coins+=int(result.order.coins)
		player.orders=result.book
		return ok(str(result.message))
	if action=="quarry" or (action=="pick" and _region==REGIONS.HOME and p==Vector2i(54,25)):
		if p!=Vector2i(54,25) or not state.board:return fail("先修好公告板，再去東北方公共採石點")
		if float(state.time)<float(state.quarry.ready):return fail("採石點正在露出新石層，約剩 %d 秒"%ceili(float(state.quarry.ready)-float(state.time)))
		state.quarry.hits+=1
		if int(state.quarry.hits)<3:return ok("採石 · 再 %d 下就能取出石材"%(3-int(state.quarry.hits)))
		give(inv,"stone",6)
		state.quarry={"hits":0,"ready":float(state.time)+45.0}
		return ok("石材 +6！新的石層約 45 秒後就緒，可和朋友輪流採集")
	if action in ["fish_start","fish_catch"]:
		if _region == REGIONS.JINGUASHI or _region in MINES.IDS:return fail("這裡沒有可垂釣的水域")
		if _region==REGIONS.Springs.REGION and REGIONS.Springs.spot(p).is_empty():return fail("請到暖泉溪或高地冷泉的岸邊拋竿")
		if _region==REGIONS.Bamboo.REGION and not REGIONS.Bamboo.water(p):return fail("請到竹澗的岸邊拋竿")
		if _region==REGIONS.StarGarden.REGION and not REGIONS.StarGarden.POOL.has_point(p):return fail("請到映星池岸邊拋竿")
		if not water(p):return fail("找一段河岸，對著水面拋竿")
		if action=="fish_start":
			if player.has("fishing"):return fail("魚竿已經放好了，等魚咬鉤後按空白鍵")
			if extra not in ["","standard"]:return fail("找不到這種釣法")
			player.fishing={"x":p.x,"y":p.y,"ready":float(state.time)+3.0}
			if extra=="standard":
				player.fishing.merge({"aligned_at":player.fishing.ready,"band":0.5,"tracked":0.0})
			return ok("魚竿放好了。等提示出現，再按空白鍵收竿")
		if not player.has("fishing"):return fail("先對水面拋竿吧")
		if int(player.fishing.x)!=p.x or int(player.fishing.y)!=p.y:return fail("請在原本的釣點收竿")
		if float(state.time)<float(player.fishing.ready):return fail("魚還沒咬鉤，再稍等一下")
		if player.fishing.has("band"):
			var now:=float(state.time)
			var tracked:=FishingTracking.progress(player.fishing,now)
			if tracked<FishingTracking.DURATION:
				player.fishing.tracked=tracked
				player.fishing.aligned_at=now
				player.fishing.band=FishingTracking.shadow(float(player.fishing.ready),now)
				return ok("已對準魚影。留在亮帶內會累積進度，滿格後收竿。")
		# T071 河岸釣魚會：已加入的島民在指定水域釣到的魚記進魚種卡後放回，
		# 不進背包、不加釣魚經驗與圖鑑（{} 表示照一般釣魚）。
		var meet_catch:=FISH_MEET.record_catch(state,token,p,_region==REGIONS.HOME)
		if not meet_catch.is_empty():return meet_catch
		var total:=int(player.get("fish_caught",0))
		var day:=WEATHER.day_index(float(state.time))
		var season:=WEATHER.season_on_day(day)
		var spot:=SALT_PAN.fishing_water(p) if _region==SALT_PAN.REGION else "coast"
		if _region==REGIONS.Springs.REGION:spot=REGIONS.Springs.spot(p)
		var result:=Collections.fishing_result(_region,season,total,player,fposmod(float(state.time),WEATHER.DAY_SECONDS),spot,WEATHER.rains(day,_region))
		var fish_id:String=result.id
		if total>=1000000000 or int(inv.get(fish_id,0))>=1000000000:return fail("釣魚紀錄或背包數量已達上限")
		if result.has("counter"):player[result.counter]=result.misses
		give(inv,fish_id,1)
		_record_discovery(player,"fish",fish_id)
		player.fish_caught=int(player.get("fish_caught",0))+1
		player.erase("fishing")
		return ok("釣到了"+FISH[fish_id].name+"！可以帶去種子攤出售")
	if action in ["cook","claim_cook","cancel_cook","queue_cook","cancel_queued_cook"]:
		var stove:Dictionary=state.objects.get(k,{})
		if stove.get("type","")!="stove":return fail("請靠近小石灶料理")
		if stove.has("cooking") and stove.has("job"):return fail(COOKING_MSG_CORRUPT)
		# T036 queue path: explicit queue actions, or any cook action on a stove
		# that already carries a `cooking` queue. Plain stoves keep the legacy job.
		if action in ["queue_cook","cancel_queued_cook"] or stove.has("cooking"):
			return _cooking_action(token,stove,action,extra)
		if action=="cook":
			if not RECIPES.has(extra):return fail("還沒有這份食譜")
			if stove.has("job"):return fail("石灶正在忙，先領取或取消目前料理")
			var recipe:Dictionary=RECIPES[extra]
			for item in recipe.ingredients:
				if int(inv.get(item,0))<int(recipe.ingredients[item]):return fail("缺少"+NAMES[item]+" %d"%recipe.ingredients[item])
			for item in recipe.ingredients:inv[item]-=int(recipe.ingredients[item])
			stove.job={"kind":extra,"ready":float(state.time)+float(recipe.time),"owner":token,"ingredients":recipe.ingredients.duplicate(true),"yield":int(recipe.yield),"recipe_version":1}
			return ok(recipe.name+"開始製作，完成後任何成員都能領取")
		if not stove.has("job"):return fail("石灶現在沒有料理")
		var job:Dictionary=stove.job
		var recipe:Dictionary=RECIPES[job.kind]
		if action=="cancel_cook":
			if job.owner!=token:return fail("只有投入食材的人可以取消")
			var original_ingredients:Dictionary=job.get("ingredients",recipe.ingredients)
			for item in original_ingredients:
				if int(inv.get(item,0))>1000000000-int(original_ingredients[item]):return fail("背包中的"+str(NAMES.get(item,item))+"已達上限，請先騰出空間再取消")
			for item in original_ingredients:give(inv,item,int(original_ingredients[item]))
			stove.erase("job")
			return ok("已取消，食材完整退回")
		if float(state.time)<float(job.ready):return fail("還要 %d 秒就好了"%ceili(float(job.ready)-float(state.time)))
		var quantity:int=int(job.get("yield",recipe.yield))
		if int(inv.get(job.kind,0))>1000000000-quantity:return fail("背包中的料理已達上限，請先騰出空間再領取")
		give(inv,job.kind,quantity)
		if Collections.is_meal(job.kind):
			_record_discovery(player,"meals",job.kind)
		player.cooked=int(player.get("cooked",0))+1
		stove.erase("job")
		return ok("完成了！%s +%d"%[recipe.name,quantity])
	if action in ["pet","feed","egg"]:
		if p!=Vector2i(45,34):return fail("請靠近糯米雞")
		if action=="pet":
			if float(state.time)-float(state.animal.last_pet)<30:return fail("糯米雞正開心地休息，過一會兒再摸摸牠")
			state.animal.last_pet=state.time
			state.animal.bond+=1
			return ok("糯米雞靠過來蹭蹭你。親密度 +1")
		if action=="feed":
			if float(state.animal.egg_ready)>=0:return fail("糯米雞已吃飽了，等牠下蛋後再餵吧")
			if int(inv.get("feed",0))<1:return fail("先用小石灶把小麥和纖維做成飼料")
			inv.feed-=1
			state.animal.egg_ready=float(state.time)+60.0
			state.animal.bond+=1
			return ok("糯米雞吃飽了！約一分鐘後可以收蛋")
		if float(state.animal.egg_ready)<0:return fail("還沒有雞蛋，先給牠一份飼料")
		if float(state.time)<float(state.animal.egg_ready):return fail("糯米雞還在準備，剩下 %d 秒"%ceili(float(state.animal.egg_ready)-float(state.time)))
		give(inv,"egg",1)
		state.animal.egg_ready=-1.0
		return ok("收到了溫暖的雞蛋！雞蛋 +1")
	if action=="picnic":
		if p!=Vector2i(40,29) or not state.board:return fail("先完成渡口公告板，再準備野餐")
		if state.picnic:return fail("野餐已經準備好了，謝謝大家！")
		var total:=0
		for item in ["soup","bread"]:
			var need:=2 if item=="soup" else 1
			var amount:=mini(need-int(state.picnic_materials[item]),int(inv.get(item,0)))
			inv[item]=int(inv.get(item,0))-amount
			state.picnic_materials[item]+=amount
			total+=amount
		if total==0:return fail("還需要兩份蘿蔔湯與一份麵包，可在小石灶製作")
		if state.picnic_materials.soup==2 and state.picnic_materials.bread==1:
			state.picnic=true
			state.community = {"table": COMMUNITY.choose_table(state)}
			for who in state.players.values():give(who.inventory,"radish_seed",3)
			return ok("野餐準備好了！每位島民收到三包蘿蔔種子，渡口也掛上了彩旗")
		return ok("料理已放上野餐桌，等大家一起補齊")
	if action == "donate":
		if p!=Vector2i(40,29): return fail("請到渡口公告板捐材料")
		if state.board: return fail("公告板已修好，河灣橋已開放！")
		var amount := 0
		for material in ["wood","stone"]:
			var required: int=30 if material=="wood" else 10
			var take := mini(required-int(state.donations[material]),int(inv.get(material,0)))
			inv[material]=int(inv.get(material,0))-take
			state.donations[material]+=take
			amount+=take
		if amount==0: return fail("還需要木材或石材，去附近採集吧")
		note_resident_participation(token,"bridge")
		if state.donations.wood>=30 and state.donations.stone>=10:
			_finish_bridge()
			return ok("工程完成！河灣橋開通了，去東邊看看吧！")
		return ok("材料已捐入，謝謝你一起建設小島")
	if action in ["buy","sell"]:
		if p!=Vector2i(43,29): return fail("請靠近小栗的種子攤")
		if action=="buy" and extra=="sapling":
			if player.coins<20:return fail("樹苗需要 20 鈴幣")
			player.coins-=20
			give(inv,"sapling",1)
			return ok("買到一棵樹苗，按 C 選樹苗，再點空地種下")
		if not CROPS.has(extra) and not FISH.has(extra) and not OTHER_SALES.has(extra): return fail("這件商品尚未上架")
		if action=="buy":
			if not CROPS.has(extra):return fail("這項物品沒有販售種子")
			if extra in FLOWER_NURSERY.FLOWERS and not FLOWER_NURSERY.home_seed_allowed(state,token,extra):return fail(FLOWER_HOME_SEED_MSG)
			var price:int=CROPS[extra].seed_price
			if player.coins<price: return fail("鈴幣不足，可以先把收成帶來出售")
			player.coins-=price
			give(inv,extra+"_seed",1)
			return ok("買到一包"+CROPS[extra].name+"種子")
		var count:int=inv.get(extra,0)
		if count<=0: return fail("背包裡沒有這種收成")
		var sale_price:int=int(CROPS[extra].price) if CROPS.has(extra) else (int(FISH[extra].price) if FISH.has(extra) else int(OTHER_SALES[extra]))
		# T093: 存檔檢查不接受超過上限的鈴幣（save_schema.whole），這裡和出貨箱一樣先擋。
		if int(player.coins)>SHIPPING.MAX_COINS-count*sale_price:return fail(COIN_CAP_MSG)
		player.coins+=count*sale_price
		inv[extra]=0
		return ok("售出 %d 個，獲得 %d 鈴幣"%[count,count*sale_price])
	if action in CHEST_MOVES:
		var box:Dictionary=state.objects.get(k,{})
		if box.get("type","") not in ["chest","private_chest","supply_box"]: return fail("這裡沒有箱子")
		var permission:=PLOT_PERMISSIONS.can_take(token,box)
		if not permission.ok:return fail(permission.message)
		if not NAMES.has(extra): return fail("無法存取這項物品")
		if not (box.get("items") is Dictionary):return fail("這裡沒有箱子")
		# T014: move 1 / half (ceil) / all of ONE stack between backpack and box.
		# Both sides keep the plain item_id -> count shape. Every check runs before
		# any mutation; a refused move changes neither side (no clamping).
		var storing:bool=action.begins_with("deposit")
		var source:Dictionary=inv if storing else box.items
		var target:Dictionary=box.items if storing else inv
		var have:=int(source.get(extra,0))
		if have<=0:return fail("背包沒有這項物品" if storing else "箱子裡沒有這項物品")
		var amount:=chest_move_amount(action,have)
		if int(target.get(extra,0))>MINE_FREIGHT.LIMIT-amount:
			return fail("箱子中的物品已達上限" if storing else "背包中的物品已達上限")
		source[extra]=have-amount
		give(target,extra,amount)
		var verb:String="存入" if storing else "取出"
		if action in ["deposit","withdraw"]:return ok("已"+verb+NAMES[extra])
		return ok("已%s%s ×%d"%[verb,NAMES[extra],amount])
	if action=="door":
		var door:Dictionary=state.objects.get(k,{})
		if door.get("type","")!="door":return fail("這裡沒有門")
		if door.get("open",false):
			for active_token in regional_tokens():
				var who:Dictionary=state.players[active_token]
				if Vector2(who.x,who.y).distance_to(Vector2(p)+Vector2(0.5,0.5))<0.8:return fail("有人站在門口，等他通過再關門")
		door.open=not door.get("open",false)
		return ok("門打開了" if door.open else "門關好了")
	if water(p) or (protected(p) and action!="remove"): return fail("這裡是水域或公共通道，請換個位置")
	var r:=resource(p)
	if action=="plant_tree":
		if r!="" or state.crops.has(k) or state.objects.has(k) or state.ground.has(k) or state.roofs.has(k):return fail("樹苗需要一格空地，不能種在農田或建物上")
		if int(inv.get("sapling",0))<1:return fail("沒有樹苗了，砍樹會得到樹苗，也可以向小栗購買")
		inv.sapling-=1
		state.forest[k]={"growth":0.0,"mature":false,"owner":token}
		player.trees_planted=int(player.get("trees_planted",0))+1
		return ok("種下了樹苗，島上有人時約三分鐘長成，不需要澆水")
	if action in ["axe","pick"]:
		if r=="": return fail("這裡沒有可採集的資源")
		if r=="sapling":return fail("小樹還在長大；自己的樹苗可用拆除工具移回背包")
		if r=="rock" and action!="pick":return fail("這是石頭，請選十字鎬")
		if r=="tree" and action!="axe":return fail("這是樹木，請選斧頭")
		state.damage[k]=int(state.damage.get(k,0))+1
		var needed:=3 if r=="tree" else 2
		if r=="grass":needed=1
		if state.damage[k]<needed:return ok("%s · 還需要 %d 下"%["砍樹" if r=="tree" else "採集",needed-int(state.damage[k])])
		player.gathering_points=mini(1000000000,int(player.get("gathering_points",0))+1)
		state.removed[k]=true
		state.forest.erase(k)
		state.damage.erase(k)
		if r=="tree":
			give(inv,"wood",6)
			give(inv,"fiber",2)
			give(inv,"sapling",1)
			give(inv,"resin",1)
		elif r=="rock":give(inv,"stone",5)
		else:give(inv,"fiber",4)
		return ok("採集完成！"+("木材 +6、纖維 +2、樹苗 +1、樹脂 +1" if r=="tree" else ("石材 +5" if r=="rock" else "纖維 +4")))
	if action=="hoe":
		if r!="" or state.objects.has(k) or state.ground.has(k):return fail("先清空地面，再開墾農田")
		if state.crops.has(k):return fail("這一格已經是農田")
		if _region==FLOWER_NURSERY.REGION:
			if not FLOWER_NURSERY.unlocked(state,token) or not FLOWER_NURSERY.own_record(state,token).intro:return fail("先向花農問好，再開墾育苗床。")
			if not FLOWER_NURSERY.NURSERY_BEDS.has_point(p):return fail(FLOWER_REJECT_MSG)
			if not FLOWER_NURSERY.plot_allowed(state.crops,token):return fail("田尾育苗床每人最多 %d 格，先收成或恢復自己的空床。"%FLOWER_NURSERY.PLOT_CAP)
		state.crops[k]={"kind":"","growth":0.0,"wet":false,"owner":token}
		return ok("農田準備好了，接著選種子播種")
	if action=="seed":
		if not CROPS.has(extra):return fail("請選擇種子")
		var crop_problem:=planting_problem(extra,p)
		if not crop_problem.is_empty():return fail(crop_problem)
		if _region==FLOWER_NURSERY.REGION and extra not in FLOWER_NURSERY.FLOWERS:return fail("田尾育苗床只種花卉：鈴蘭藍花、蜜橙花或風鈴香草。")
		if not state.crops.has(k):return fail("先用鋤頭開墾一格農田")
		var permission:=PLOT_PERMISSIONS.can_place(self,token,p,"seed:"+extra)
		if not permission.ok:return fail(permission.message)
		if state.crops[k].kind!="":return fail("這格已經種了作物")
		if int(inv.get(extra+"_seed",0))<=0:return fail("種子用完了，可向渡口的小栗購買")
		inv[extra+"_seed"]-=1
		state.crops[k].kind=extra
		state.crops[k].growth=0.0
		state.crops[k]["remaining"]=int(CROPS[extra].get("cycles",1))
		if _region==FLOWER_NURSERY.REGION:FLOWER_NURSERY.note_plant(state,token,extra)
		if not greenhouse_covers(k) and not crop_grows_in_season(extra,_region,p,float(state.time)):
			return ok("種下%s。現在不是它的季節，會休眠到%s季再生長。"%[CROPS[extra].name,crop_season_text(extra)])
		return ok("種下"+CROPS[extra].name+"，記得澆水")
	if action=="water":
		if not state.crops.has(k):return fail("請對農田澆水")
		state.crops[k].wet=true
		return ok("水分充足，幼苗會慢慢長大")
	if action=="plot_harvest_access":
		if not state.crops.has(k) or state.crops[k].get("owner","")!=token:return fail("只有田主能調整採收權限。")
		if _region==FLOWER_NURSERY.REGION:return fail("田尾育苗床固定由田主採收。")
		var crop:Dictionary=state.crops[k]
		if extra.begins_with("friend:"):
			var public_id:=extra.trim_prefix("friend:")
			for guest in regional_tokens():
				if guest!=token and guest.sha256_text().left(16)==public_id:
					crop.harvest_friend=guest
					crop.harvest_access="friend"
					return ok("採收權限已更新。")
			return fail("請選擇同區在線的玩家。")
		if extra not in ["owner","island"]:return fail("請選擇有效的採收權限。")
		crop.erase("harvest_friend")
		crop.harvest_access=extra
		return ok("採收權限已更新。")
	if action=="harvest":
		if not state.crops.has(k) or state.crops[k].kind=="":return fail("這裡沒有作物")
		var crop:Dictionary=state.crops[k]
		var permission:=PLOT_PERMISSIONS.can_harvest(self,token,crop)
		if not permission.ok:return fail(permission.message)
		if crop.growth<float(CROPS[crop.kind].time):
			if not greenhouse_covers(k) and not crop_grows_in_season(crop.kind,_region,p,float(state.time)):
				return fail("作物正在休眠，等到適合的季節會繼續生長。")
			return fail("還沒成熟，"+("先澆點水吧" if not crop.wet else "再等 %d 秒"%ceili(float(CROPS[crop.kind].time)-float(crop.growth))))
		var crop_name:String=CROPS[crop.kind].name
		var harvested_kind:String=crop.kind
		# T018: same per-item / counter ceiling as harvest_area and SaveSchema.whole; refuse before any mutation.
		if int(inv.get(harvested_kind,0))>1000000000-int(CROPS[harvested_kind].yield):return fail("背包中的"+crop_name+"已達上限，作物留在田裡。")
		if int(player.harvests)>=1000000000:return fail("採收紀錄已達上限，作物留在田裡。")
		var count:=_harvest_plot(token,player,crop,k)
		if _region==FLOWER_NURSERY.REGION:FLOWER_NURSERY.note_harvest(state,token,harvested_kind,count)
		return ok("收成了！%s +%d。"%[crop_name,count]+("%s還能再收 %d 次，記得重新澆水"%[crop_name,int(crop.remaining)] if crop.kind!="" else "可以出售或帶去做料理"))
	if action=="build":return _build_piece(token,p,extra)
	if action=="remove":
		# protected() is bypassed for remove above, so donated cells need this guard.
		if _region==REGIONS.HOME and PUBLIC_KITCHEN.is_site_cell(state,p):return fail(PUBLIC_KITCHEN.MSG_LOCKED)
		if state.forest.has(k):
			var permission:=PLOT_PERMISSIONS.can_dismantle(self,token,p)
			if not permission.ok:return fail(permission.message)
			if state.forest[k].mature and gathering_level(player)<SAPLING_RECOVERY_LEVEL:
				return fail("成熟的自種樹可在採集三級後回收為樹苗。")
			if int(inv.get("sapling",0))>=1000000000:return fail("背包中的樹苗已達上限")
			state.forest.erase(k)
			give(inv,"sapling",1)
			return ok("樹苗已移回背包，可以換個位置再種")
		if state.crops.has(k) and not greenhouse_covers(k):
			if state.crops[k].kind!="":return fail("田裡還有作物，收成後才能恢復草地")
			var permission:=PLOT_PERMISSIONS.can_dismantle(self,token,p)
			if not permission.ok:return fail(permission.message)
			state.crops.erase(k)
			return ok("空農田恢復成草地，可以重新規劃家園了")
		# Automatic roofs are skipped: the object/floor beneath is targeted with
		# its usual owner/busy/contents guards; the roof follows via reconcile.
		var layer_name:=_remove_layer(k)
		if layer_name=="":return fail("這裡沒有可拆除的建物")
		var source:Dictionary=state[layer_name]
		var obj:Dictionary=source[k]
		var permission:=PLOT_PERMISSIONS.can_dismantle(self,token,p)
		if not permission.ok:return fail(permission.message)
		if obj.type=="conveyor" and (obj.enabled or not obj.items.is_empty()):return fail("請停用並清空輸送帶")
		if obj.type=="mine_drill" and not MINE_DRILL.can_move(obj):return fail("請停用並清空採掘機。")
		if obj.type=="waterworks" and not WATERWORKS.can_move(obj):return fail("請停用並清空水力加工台。")
		if (obj.type in LOGISTICS.PROCESSORS or obj.type in ["seed_maker","loom","glass_furnace"]) and not LOGISTICS.processing_idle(obj):return fail(PROCESSING_MSG_BUSY)
		if obj.type in LOGISTICS.PROCESSORS and not LOGISTICS.processor_ready_to_move(obj):return fail("請停用自動加工並清空設備")
		if obj.type=="forester" and not FORESTRY.can_move(obj):return fail("請先停用林務站並取回全部材料")
		if obj.has("job"):return fail("設備仍在工作，先領取或取消再拆除")
		if obj.has("cooking") and not cooking_idle(obj):return fail(COOKING_MSG_BUSY)
		for amount in obj.get("items",{}).values():
			if int(amount)>0:return fail("箱子還有物品，先取出再拆除")
		var recipe:Dictionary=BUILD[obj.type]
		for item in recipe:
			if item!="name" and int(inv.get(item,0))+int(recipe[item])>1000000000:
				return fail("背包中的物品已達上限")
		for item in recipe:
			if item!="name":give(inv,item,int(recipe[item]))
		source.erase(k)
		return ok("已拆除，建造材料完整退還")
	return fail("請選擇工具後再試一次")

## Beimen allow-list (contract rejected_in_beimen as corrected by the lead).
## travel/transit/rescue/claim_milestone are resolved before this gate.
func _salt_allowed(action: String, p: Vector2i, extra: String) -> bool:
	if action in SALT_PAN.ACTIONS or action in CHEST_MOVES:return true
	if action in ["fish_start","fish_catch"]:return not SALT_PAN.land(p)
	if action=="build":return extra in SALT_BOXES and SALT_PAN.chest_socket_lot(p)>=0
	if action=="remove":return SALT_PAN.chest_socket_lot(p)>=0
	return false

## Salt action dispatch: beimen actions only in beimen, salt_letter/salt_order
## only at Xiaoli's stall at home (reach already checked). SaltPan always gets
## the beimen objects layer and the world clock. For salt_auto_cfg the chosen
## chest gets a material-source box_id first (same generator as
## prepare_material_box); act() rolls it back if the action fails.
func _salt_action(token: String, action: String, p: Vector2i, extra: String) -> Dictionary:
	if action in SALT_PAN.HOME_ACTIONS:
		if _region!=REGIONS.HOME or p!=FLOWER_NURSERY.RECEIVER_HOME:return fail(SALT_HOME_MSG)
	elif _region!=SALT_PAN.REGION:return fail(SALT_REGION_MSG)
	var objects:Dictionary=state.objects if _region==SALT_PAN.REGION else state.regions[SALT_PAN.REGION].objects
	if action=="salt_auto_cfg":
		var target:Dictionary=_salt_cfg_chest(token,extra,objects)
		if not target.is_empty() and not target.has("box_id"):
			var id:String=MATERIAL_SOURCES._new_box_id(self)
			if id=="":return fail(MATERIAL_SOURCES.MSG_ID)
			target.box_id=id
	var was_repaired:bool=float(state.salt_pan.get("repaired_at",-1.0))>=0.0
	var events_before:int=state.events.size()
	var result:Dictionary=SALT_PAN.apply(state,token,action,_region,p,extra,objects,float(state.time))
	if result.get("ok",false)==true and action=="salt_gate_give" and not was_repaired and float(state.salt_pan.get("repaired_at",-1.0))>=0.0:
		# Broadcast the repair exactly once (SaltPan may already have pushed it).
		if not state.events.slice(events_before).has(SALT_PAN.GATE_EVENT):state.events.append(SALT_PAN.GATE_EVENT)
	return result

## The chest a salt_auto_cfg extra "x,y|cap" names when it is a shared chest or
## the actor's own private chest (anything else: {} and SaltPan rejects).
func _salt_cfg_chest(token: String, extra: String, objects: Dictionary) -> Dictionary:
	var parts:PackedStringArray=extra.split("|")
	if parts.size()!=2:return {}
	var parsed:Dictionary=CONSTRUCTION_HISTORY.parse_tile(parts[0])
	if not parsed.ok:return {}
	var box=objects.get(parts[0])
	if not box is Dictionary or str(box.get("type","")) not in SALT_BOXES:return {}
	if not PLOT_PERMISSIONS.can_take(token,box).ok:return {}
	return box

## Single-piece build rules shared by `build` and blueprints. Callers have
## already applied the region/distance/water/protected gates of _apply.
## charge=false (blueprint simulation only) skips ONLY the inventory check and
## debit; every placement, unlock, limit and collision rule still applies.
func _build_piece(token: String, p: Vector2i, extra: String, charge: bool = true) -> Dictionary:
	var player: Dictionary=state.players[token]
	var inv: Dictionary=player.inventory
	var k := key(p)
	var r:=resource(p)
	if not BUILD.has(extra):return fail("尚未解鎖這個物件")
	if extra in ["author_sign","author_shelf"] and crafting_level(player)<10:return fail("手作達到十級後解鎖工匠家具。")
	if extra=="expedition_tent" and exploration_level(exploration_points(player))<EXPEDITION_TENT_LEVEL:return fail("探索達到十級後解鎖探險紀念帳篷。")
	if extra=="supply_box" and exploration_level(exploration_points(player))<SUPPLY_BOX_LEVEL:return fail("探索達到六級後可放置便攜補給箱。")
	if extra=="fish_display" and Collections.angling_level(player)<Collections.FISH_DISPLAY_LEVEL:return fail("漁獵觀察達到十級後，即可建造島岸魚譜展示櫃。")
	if extra=="master_flower_bed" and farming_level(player)<MASTER_FARMING_LEVEL:return fail("農耕達到十級後，即可建造豐收花圃。")
	if extra=="greenhouse_rack" and not player.get("greenhouse_reported",false):return fail("完成星禾的「冬天也開花」後解鎖。")
	if extra=="medium_sprinkler" and farming_level(player)<MEDIUM_SPRINKLER_LEVEL:return fail("農耕達到六級後，即可建造中型灑水器。")
	if extra=="seed_maker" and farming_level(player)<SEED_MAKER_LEVEL:return fail("農耕達到三級後，即可建造種子機。")
	if extra=="glass_furnace" and not MINES.hoist_ready(state.mine_depths):return fail(GLASS_FURNACE_LOCKED_MSG)
	if extra in KITCHEN_GATED and not kitchen_opened():return fail(MILL_LOCKED_MSG)
	if _region==SALT_PAN.REGION:
		var permission:=PLOT_PERMISSIONS.can_place(self,token,p,extra)
		if not permission.ok:return fail(permission.message)
	if extra=="mine_drill":
		if int(state.mine_depths.unlocked)<5:return fail("先完成第四層礦道工程。")
		if _region in MINES.IDS and _region not in MINE_DRILL.REGIONS:return fail("採掘機只能設在第一至第五層；深層礦道請手動開採。")
		if _region not in MINES.IDS or MINE_DRILL.placement(p)<0:return fail("採掘機須放在礦層指定礦點的相鄰空地。")
		if state.objects.values().any(func(device):return device.type=="mine_drill"):return fail("本層已設置一台採掘機。")
		if device_count(token,"mine_drill")>=MINE_DRILL.LIMIT:return fail("每人最多兩台採掘機。")
	if extra=="waterworks":
		if int(state.mine_depths.unlocked)<4:return fail("先完成礦場第三層的抽水工程。")
		if device_count(token,"waterworks")>=WATERWORKS.LIMIT:return fail("每人最多四台水力加工台。")
	if not Village.unlocked(player,extra):return fail("完成居民委託就能取得這張圖樣，按 J 查看故事")
	if extra=="greenhouse_roof":
		if state.roofs.has(k):return fail("這裡已經有屋頂")
		if WEATHER.is_indoor(_region):return fail("溫室玻璃棚需要露天農田")
		var permission:=PLOT_PERMISSIONS.can_place(self,token,p,extra)
		if not permission.ok:return fail(permission.message)
	elif extra=="roof":
		if state.roofs.has(k):return fail("這裡已經有屋頂")
		if not state.ground.has(k) or state.ground[k].type!="floor":return fail("先鋪木地板，再蓋上屋頂")
		var permission:=PLOT_PERMISSIONS.can_place(self,token,p,extra)
		if not permission.ok:return fail(permission.message)
	elif r!="" or state.crops.has(k) or state.objects.has(k):return fail("這格有東西，請選空地")
	if extra in ["floor","path"] and state.ground.has(k):return fail("這裡已經鋪好了")
	if extra=="water_pump" and not INDUSTRY.near_river(self,p):return fail("水泵需放在河水兩格內的陸地")
	if extra in ["sprinkler","medium_sprinkler","forester","conveyor"] or INDUSTRY.LIMITS.has(extra):
		var limit:int={"sprinkler":SPRINKLER_LIMIT,"medium_sprinkler":SPRINKLER_LIMIT,"forester":FORESTRY.LIMIT,"conveyor":LOGISTICS.BELT_LIMIT}.get(extra,INDUSTRY.LIMITS.get(extra,0))
		var owned:=0
		for device in state.objects.values():
			if device.type==extra and device.owner==token:owned+=1
		if owned>=limit:return fail("已達此設備的每人放置上限")
	if extra in ["ore_display","wall","window","door","chest","private_chest","supply_box","bench","bed","table","stove","long_bench","sofa","planter","greenhouse_rack","master_flower_bed","fish_display","author_sign","author_shelf","expedition_tent","sprinkler","medium_sprinkler","water_tank","water_tower","water_pump","waterworks","mine_drill","sawmill","charcoal_kiln","forester","mill","seed_maker","loom","glass_furnace"]:
		for active_token in regional_tokens():
			var who:Dictionary=state.players[active_token]
			if Vector2(who.x,who.y).distance_to(Vector2(p)+Vector2(0.5,0.5))<0.8:return fail("這裡有人，請留出空間")
	var recipe:Dictionary=BUILD[extra]
	if charge:
		for item in recipe:
			if item=="name":continue
			if int(inv.get(item,0))<int(recipe[item]):return fail("材料不足，需要"+NAMES[item]+" %d"%int(recipe[item]))
		for item in recipe:
			if item!="name":give(inv,item,-int(recipe[item]))
	var obj:Dictionary={"type":extra,"owner":token,"items":{}}
	if extra in ["author_sign","author_shelf","expedition_tent"]:obj.author=player.name
	if INDUSTRY.SPRINKLER_CAPACITIES.has(extra):obj.merge({"water":0,"enabled":false,"next_water":float(state.time),"last_water":-1.0})
	if extra=="conveyor":obj.merge(LOGISTICS.fresh())
	# Legacy sawmill/kiln keep `input_wood`; the mill buffers wheat in `input_wheat`.
	if extra in LOGISTICS.PROCESSORS:obj.merge({LOGISTICS.input_field(extra):0,"auto_enabled":false})
	if extra=="forester":obj.merge(FORESTRY.fresh(float(state.time)))
	if extra=="mine_drill":obj.merge(MINE_DRILL.fresh(MINE_DRILL.placement(p)),true)
	if extra=="waterworks":obj.merge(WATERWORKS.fresh(),true)
	if extra=="water_tank":obj.water=0
	if extra=="water_pump":obj.enabled=false
	if extra==INDUSTRY.GATE_KIND:obj.mode="open"
	if extra==INDUSTRY.TOWER_KIND:obj.merge({"water":0,"enabled":true})
	if extra=="door":obj.open=false
	if extra in BLUEPRINT_DESIGN.ROOF_KINDS:state.roofs[k]=obj
	elif extra in ["floor","path"]:state.ground[k]=obj
	else:state.objects[k]=obj
	player.builds+=1
	return ok("放好了"+recipe.name+"，家園又多了一點你的心意")

# ---------------------------------------------------------------------------
# Blueprint stage two (docs/blueprint-integration.md): authoritative quote and
# atomic apply. Backend only; Session/UI wiring is a later stage.
# ---------------------------------------------------------------------------

const BLUEPRINT_RANGE := 3.2
const BLUEPRINT_MAX_PROBLEMS := 32
const BLUEPRINT_RECEIPT := "blueprint:"
const BLUEPRINT_HASH_VERSION := 1
const BLUEPRINT_ITEM_CAP := 1000000000

static func _blueprint_public() -> Dictionary:
	return {"ok":false,"message":"","cost":{},"mine_refund":{},"others_refund":{},"other_people":0,
		"roof_add":0,"roof_remove":0,"pieces":0,"problems":[],"hash":"","undoable":false}

static func _is_lower_hex(value: String, length: int) -> bool:
	if value.length()!=length:return false
	for i in length:
		var ch:=value.unicode_at(i)
		if not ((ch>=48 and ch<=57) or (ch>=97 and ch<=102)):return false
	return true

## Sorted fresh int copy of a material map.
static func _sorted_counts(counts: Dictionary) -> Dictionary:
	var names:Array=counts.keys()
	names.sort()
	var out:={}
	for item in names:out[str(item)]=int(counts[item])
	return out

## Read-only. Never mutates live state, orientation, receipts, undo clocks or
## the save file: everything is staged on an independent World copy.
func quote_blueprint(token: String, raw: Variant, origin: Vector2i, turns: Variant = 0) -> Dictionary:
	return _blueprint_prepare(token,raw,origin,turns).quote

## {quote: public quote, commit: {} | staged data for apply_blueprint}.
func _blueprint_prepare(token: String, raw: Variant, origin: Vector2i, turns: Variant) -> Dictionary:
	var quote:=_blueprint_public()
	var out:={"quote":quote,"commit":{}}
	var players=state.get("players")
	if not players is Dictionary or not players.has(token):
		quote.message="尚未加入世界"
		return out
	var rotated:Dictionary=BLUEPRINT_DESIGN.rotate(raw,turns,BUILD,NAMES)
	if not rotated.ok:
		quote.message=str(rotated.reason)
		return out
	var bp:Dictionary=rotated.blueprint
	var region:=player_region(token)
	out.commit=_blueprint_stage(token,bp,region,origin,quote)
	# Hash binds the normalized layout, region, origin, rotation and the full
	# outcome (prices, roof cells, refunds, problems). No identities inside.
	quote.hash=CONSTRUCTION_HISTORY.canonical({"v":BLUEPRINT_HASH_VERSION,"region":region,"origin":[origin.x,origin.y],
		"turns":int(turns),"blueprint":bp,"ok":quote.ok,"message":quote.message,"cost":quote.cost,
		"mine_refund":quote.mine_refund,"others_refund":quote.others_refund,"other_people":quote.other_people,
		"roof_cells":out.commit.get("roof_cells",[]),"roof_add":quote.roof_add,"roof_remove":quote.roof_remove,
		"pieces":quote.pieces,"problems":quote.problems,"undoable":quote.undoable}).sha256_text()
	return out

## Fills `quote` in place; returns commit data only when everything passed.
func _blueprint_stage(token: String, bp: Dictionary, region: String, origin: Vector2i, quote: Dictionary) -> Dictionary:
	var pieces:Array=bp.pieces
	quote.pieces=pieces.size()
	var base:Dictionary=BLUEPRINT_DESIGN.base_cost(bp,BUILD,NAMES)
	if not base.ok:
		quote.message=str(base.reason)
		return {}
	quote.cost=_sorted_counts(base.cost)
	if region not in REGIONS.ALL or not state.regions is Dictionary or (region!=REGIONS.HOME and not state.regions.has(region)):
		quote.message="區域資料有誤，這次沒有施工"
		return {}
	if region in TRANSIT.LOCAL:
		quote.message="公共站場只供步行與轉乘，請回農地或礦區作業。"
		return {}
	if region==FLOWER_NURSERY.REGION:
		quote.message=FLOWER_REJECT_MSG
		return {}
	if region==SALT_PAN.REGION:
		quote.message=SALT_PAN.REJECT_MESSAGE
		return {}
	if absi(origin.x)>BLUEPRINT_DESIGN.COORD_LIMIT or absi(origin.y)>BLUEPRINT_DESIGN.COORD_LIMIT:
		quote.message="藍圖位置超出範圍"
		return {}
	var person:Dictionary=state.players[token]
	if Vector2(float(person.x),float(person.y)).distance_to(Vector2(origin)+Vector2(0.5,0.5))>BLUEPRINT_RANGE:
		quote.message="藍圖起點要在身邊三格內"
		return {}
	# Independent candidate world (cannot preload World here: get_script()).
	var sim=get_script().new()
	sim.state=state.duplicate(true)
	sim._region=_region
	sim.active_tokens=active_tokens.duplicate()
	sim.switch_region(region)
	var sim_layers:Dictionary=sim._layers_of(region)
	var prior:={}
	for field in CONSTRUCTION_HISTORY.TILE_LAYERS:
		var layer:Dictionary=sim_layers[field]
		# Pieces only add entries, so shallow copies freeze the "before" layers.
		prior[field]=layer.duplicate() if field in CONSTRUCTION_UNDO.LAYERS else layer
	var problems:Array=[]
	var problem_count:=0
	var touched:Array[Vector2i]=[]
	var topology:={}
	var cells:={}
	for item in pieces:
		var piece:Dictionary=item
		var kind:=str(piece.kind)
		var c:=origin+Vector2i(int(piece.x),int(piece.y))
		var reason:String=sim._blueprint_piece(token,c,kind,piece.get("settings",{}),str(piece.get("style","")))
		if reason!="":
			problem_count+=1
			if problems.size()<BLUEPRINT_MAX_PROBLEMS:problems.append({"x":c.x,"y":c.y,"kind":kind,"reason":reason})
			continue
		cells[key(c)]=true
		if kind in AUTO_ROOF_BUILDS and not topology.has(c):
			topology[c]=true
			touched.append(c)
	quote.problems=problems
	if problem_count>0:
		quote.message="有 %d 個位置無法施工，請調整位置或旋轉"%problem_count
		return {}
	if int(sim.state.players[token].get("builds",0))>BLUEPRINT_ITEM_CAP:
		quote.message="施工紀錄已達上限，這次沒有施工"
		return {}
	# One auto-roof pass over the final layout (never per piece).
	var plan:Dictionary={"ok":true,"message":"","add":{},"remove":[],"cost":{},"refunds":{}}
	if not touched.is_empty():
		var after:={"ground":sim.state.ground,"objects":sim.state.objects,"roofs":sim.state.roofs}
		plan=AUTO_ROOF_PLAN.reconcile({"ground":prior.ground,"objects":prior.objects,"roofs":prior.roofs},after,touched,token,BUILD.roof)
		if not plan.ok:
			quote.message=str(plan.message)
			return {}
		for roof_key in plan.add:
			var below=sim.state.ground.get(roof_key)
			var roof=plan.add[roof_key]
			if sim.state.roofs.has(roof_key) or not (below is Dictionary) or str(below.get("type",""))!="floor":
				quote.message="屋頂施工計畫有誤，這次沒有施工"
				return {}
			if typeof(below.get("owner"))!=TYPE_STRING or not sim.state.players.has(below.owner):
				quote.message="地板資料有誤，這次沒有施工"
				return {}
			if not (roof is Dictionary) or roof.get("owner")!=token or not is_auto_roof(roof) or roof.get("type")!="roof":
				quote.message="屋頂施工計畫有誤，這次沒有施工"
				return {}
		for roof_key in plan.remove:
			if not is_auto_roof(sim.state.roofs.get(roof_key)):
				quote.message="屋頂施工計畫有誤，這次沒有施工"
				return {}
	# Aggregate gross cost (base + auto roofs); refunds listed separately.
	var total:Dictionary=quote.cost.duplicate()
	for item in plan.cost:
		total[item]=int(total.get(item,0))+int(plan.cost[item])
		if int(total[item])>BLUEPRINT_ITEM_CAP:
			quote.message="藍圖材料總量超出上限"
			return {}
	quote.cost=_sorted_counts(total)
	var refunds:Dictionary=plan.refunds
	var mine:Dictionary=refunds.get(token,{})
	var others:={}
	var other_people:=0
	for owner in refunds:
		if owner==token:continue
		other_people+=1
		for item in refunds[owner]:others[item]=int(others.get(item,0))+int(refunds[owner][item])
	quote.mine_refund=_sorted_counts(mine)
	quote.others_refund=_sorted_counts(others)
	quote.other_people=other_people
	quote.roof_add=plan.add.size()
	quote.roof_remove=plan.remove.size()
	# Single settlement over the merged cost; the simulation never charged, so
	# the actor's real inventory must cover everything at once.
	var settled:Dictionary=AUTO_ROOF_SETTLEMENT.prepare(sim.state.players,token,
		{"ok":true,"message":"","add":plan.add,"remove":plan.remove,"cost":quote.cost,"refunds":refunds})
	if not settled.ok:
		if settled.message==AUTO_ROOF_SETTLEMENT.MSG_MISSING:
			var inv:Dictionary=sim.state.players[token].inventory
			var short:={}
			for item in quote.cost:
				var have:=int(inv.get(item,0))+int(mine.get(item,0))
				if have<int(quote.cost[item]):short[item]=int(quote.cost[item])-have
			quote.message="材料不足，還缺 "+_amounts(short,"")
		else:quote.message=str(settled.message)
		return {}
	# Stage the full final candidate (roofs + inventories) in the copy.
	for roof_key in plan.remove:sim.state.roofs.erase(roof_key)
	for roof_key in plan.add:sim.state.roofs[roof_key]=(plan.add[roof_key] as Dictionary).duplicate(true)
	var staged:Dictionary=settled.inventories
	for owner in staged:sim.state.players[owner].inventory=(staged[owner] as Dictionary).duplicate(true)
	var undoable:=false
	var history:=_history()
	if not history.is_empty() and int(history.serial)<CONSTRUCTION_HISTORY.MAX_SERIAL and _undo_utc()>=0.0 and _undo_ticks()>=0 and pieces.size()<=CONSTRUCTION_HISTORY.MAX_BLUEPRINT_BUILDS:
		undoable=bool(_undo_record(prior,sim._layers_of(region),state.players,sim.state.players,token).ok)
	quote.undoable=undoable
	var roof_cells:Array=[]
	for roof_key in plan.add:roof_cells.append("+"+str(roof_key))
	for roof_key in plan.remove:roof_cells.append("-"+str(roof_key))
	roof_cells.sort()
	for roof_key in plan.add:cells[str(roof_key)]=true
	for roof_key in plan.remove:cells[str(roof_key)]=true
	var parts:PackedStringArray=["已可依藍圖「%s」施工 %d 件，材料 %s"%[bp.name,pieces.size(),_amounts(quote.cost,"−")]]
	if not mine.is_empty():parts.append("退回你 %s"%_amounts(mine,"+"))
	if other_people>0:parts.append("另有 %d 位原出資者收到屋頂退料"%other_people)
	if not undoable:parts.append("這次施工完成後無法復原")
	quote.ok=true
	quote.message="；".join(parts)
	return {"sim":sim,"cells":cells,"inventories":staged,"plan":plan,"region":region,"name":str(bp.name),
		"pieces":pieces.size(),"roof_cells":roof_cells}

## One blueprint piece on the (simulated, region-oriented) world. "" = placed.
## Same terrain gates as _apply plus the blueprint-only rules: no overwrite,
## objects never on another player's ground. Range is the blueprint's own.
func _blueprint_piece(token: String, c: Vector2i, kind: String, settings: Variant, style: String = "") -> String:
	if not is_land(c):return "超出可施工的地形"
	if PLOT_PERMISSIONS.public_area(self,c):return PLOT_PERMISSIONS.MSG_PUBLIC
	var k:=key(c)
	var permission:=PLOT_PERMISSIONS.blueprint_floor(self,token,c,kind)
	if not permission.ok:return permission.message
	var result:=_build_piece(token,c,kind,false)
	if not result.ok:return str(result.message)
	if not style.is_empty():state[BUILD_STYLES.expected_layer(kind)][k].style=style
	if kind=="conveyor" and settings is Dictionary and settings.has("dir") and settings.has("filter"):
		var belt:Dictionary=state.objects[k]
		belt.dir=int(settings.dir)
		belt.filter=str(settings.filter)
	return ""

## Read-only lookup of this player's committed blueprint request.
func blueprint_receipt(token: String, nonce: String) -> Dictionary:
	# Read-only lookup for an authenticated Session retry after travel/reconnect.
	# Never normalize orientation or return a reference into the saved world.
	if not _is_lower_hex(nonce,32):return {}
	var players=state.get("players")
	if not players is Dictionary or not players.has(token):return {}
	var receipts=players[token].get("receipts")
	if not receipts is Dictionary:return {}
	var stored=receipts.get(BLUEPRINT_RECEIPT+nonce)
	if not stored is Dictionary or stored.get("blueprint")!=true or stored.get("ok")!=true:return {}
	return stored.duplicate(true)

## Atomic blueprint construction. Requotes; a different hash returns
## {ok:false, requote:true, quote} without building. Success writes every piece,
## auto roof and inventory, observes/captures undo once, stores a compact
## receipt under "blueprint:"+nonce and saves exactly once; any failure
## restores the pre-call state and stores no receipt.
func apply_blueprint(token: String, nonce: String, raw: Variant, origin: Vector2i, turns: Variant, expected_hash: String) -> Dictionary:
	if not state.players.has(token):return fail("尚未加入世界")
	if not _is_lower_hex(nonce,32):return fail("施工編號無效，請重新報價")
	if not _is_lower_hex(expected_hash,64):return fail("報價資料無效，請重新報價")
	switch_region(REGIONS.HOME)
	var receipt_id:=BLUEPRINT_RECEIPT+nonce
	var player:Dictionary=state.players[token]
	if player.receipts.has(receipt_id):
		var stored=player.receipts[receipt_id]
		if stored is Dictionary and stored.get("blueprint")==true:return (stored as Dictionary).duplicate(true)
		return fail("施工編號無效，請重新報價")
	var prepared:=_blueprint_prepare(token,raw,origin,turns)
	var quote:Dictionary=prepared.quote
	if quote.hash!=expected_hash:
		return {"ok":false,"requote":true,"message":"現場狀況或價格已變動，請確認新的報價","quote":quote}
	var commit:Dictionary=prepared.commit
	if not quote.ok or commit.is_empty():
		return {"ok":false,"message":str(quote.message),"quote":quote}
	var before:=state.duplicate(true)
	var region:String=commit.region
	var builds_before:=int(player.get("builds",0))
	var sim=commit.sim
	switch_region(region)
	for layer in CONSTRUCTION_UNDO.LAYERS:
		var target:Dictionary=state[layer]
		var source:Dictionary=sim.state[layer]
		for tile in commit.cells:
			if source.has(tile):target[tile]=(source[tile] as Dictionary).duplicate(true)
			else:target.erase(tile)
	switch_region(REGIONS.HOME)
	var inventories:Dictionary=commit.inventories
	for owner in inventories:state.players[owner].inventory=(inventories[owner] as Dictionary).duplicate(true)
	player=state.players[token]
	player.builds=builds_before+int(commit.pieces)
	var message:="已依藍圖「%s」施工 %d 件，材料已扣除"%[commit.name,int(commit.pieces)]
	var plan:Dictionary=commit.plan
	if not plan.add.is_empty() or not plan.remove.is_empty():message+="；"+_auto_roof_summary(token,plan)
	# Same transaction as act(): observe older records, then record this whole
	# blueprint once as the actor's last construction.
	_undo_observe({})
	_undo_capture(token,region,"blueprint","藍圖「%s」"%commit.name,before,builds_before)
	player=state.players[token]
	state.committed+=1
	var result:={"ok":true,"message":message,"blueprint":true,"pieces":int(commit.pieces),
		"roof_add":int(quote.roof_add),"roof_remove":int(quote.roof_remove),"cost":quote.cost.duplicate(),"hash":expected_hash}
	player.receipts[receipt_id]=result
	while player.receipts.size()>128:player.receipts.erase(player.receipts.keys()[0])
	# T015: same atomic save as the pieces, inventories and receipt.
	var journal_entry:=_ledger_commit("blueprint",token,receipt_id,before,result)
	if not save():
		_restore(before)
		if not journal_entry.is_empty():_ledger_reject("blueprint",token,receipt_id,SAVE_FAILED_MSG,true)
		_prune_undo_ticks()
		return {"ok":false,"message":SAVE_FAILED_MSG}
	_ledger_pending.clear()
	_prune_undo_ticks()
	return result.duplicate(true)

func device_count(token:String,kind:String)->int:
	var count:=0
	for local in [state.objects]+state.regions.values().map(func(region):return region.objects):
		for device in local.values():
			if device.type==kind and device.owner==token:count+=1
	return count

func operate_logistics(token:String,k:String,action:String,extra:String) -> Dictionary:
	var device:Dictionary=state.objects.get(k,{})
	var conveyor:=action in ["configure_conveyor","toggle_conveyor","unload_conveyor"]
	if device.is_empty() or device.owner!=token or (device.type!="conveyor" if conveyor else device.type not in LOGISTICS.PROCESSORS):
		return fail("只能操作自己的設備")
	var inventory:Dictionary=state.players[token].inventory
	if action=="toggle_auto_processing" and device.has("processing"):
		# A queue never coexists with auto mode or a job. Busy (or malformed)
		# queues block enabling auto; an empty queue is dropped atomically with
		# the toggle. input_wood/items buffers are untouched.
		if device.get("auto_enabled",false) or device.has("job"):return fail(PROCESSING_MSG_CORRUPT)
		if not LOGISTICS.processing_idle(device):return fail(PROCESSING_MSG_BUSY)
		device.erase("processing")
	match action:
		"configure_conveyor":
			if device.enabled or not device.items.is_empty():return fail("請停用並清空輸送帶")
			var option:=extra.split(":")
			if option.size()!=2:return fail("無效的輸送帶設定")
			if option[0]=="dir" and option[1] in ["0","1","2","3"]:device.dir=int(option[1])
			elif option[0]=="filter" and option[1] in LOGISTICS.FILTERS:device.filter=option[1]
			else:return fail("無效的輸送帶設定")
		"toggle_conveyor":device.enabled=not device.enabled
		"toggle_auto_processing":device.auto_enabled=not device.get("auto_enabled",false)
		"feed_processing":
			# Station-specific buffer: wood/input_wood (sawmill, kiln), wheat/input_wheat (mill).
			var input_item:=LOGISTICS.input_item(str(device.type))
			var input_field:=LOGISTICS.input_field(str(device.type))
			var amount:=mini(4,mini(int(inventory.get(input_item,0)),LOGISTICS.PROCESS_INPUT_CAP-int(device.get(input_field,0))))
			if amount<=0:return fail("背包無%s或輸入緩衝已滿"%str(NAMES.get(input_item,input_item)))
			give(inventory,input_item,-amount)
			device[input_field]=int(device.get(input_field,0))+amount
		_:
			var payout:Dictionary=device.items if action!="unload_processing_input" else {LOGISTICS.input_item(str(device.type)):device.get(LOGISTICS.input_field(str(device.type)),0)}
			var any:=false
			for item in payout:
				any=any or int(payout[item])>0
				if int(inventory.get(item,0))+int(payout[item])>1000000000:return fail("背包中的物品已達上限")
			if not any:return fail("目前沒有可取回的物品")
			for item in payout:
				if int(payout[item])>0:give(inventory,item,int(payout[item]))
			if action=="unload_processing_input":device[LOGISTICS.input_field(str(device.type))]=0
			else:device.items.clear()
	return ok("設備已更新")

func operate_forester(token:String,k:String,action:String,item:String) -> Dictionary:
	var station:Dictionary=state.objects.get(k,{})
	if station.get("type","")!="forester" or station.owner!=token:return fail("只能操作自己的林務站")
	var inv:Dictionary=state.players[token].inventory
	if action=="toggle_forester":
		station.enabled=not station.enabled
		return ok("林務站已啟用" if station.enabled else "林務站已停用")
	if action=="load_forester":
		if item not in ["charcoal","sapling"]:return fail("林務站只接受木炭或樹苗")
		var field:="fuel" if item=="charcoal" else "saplings"
		var quantity:=mini(4,mini(FORESTRY.CAPACITY-int(station[field]),int(inv.get(item,0))))
		if quantity<=0:return fail("背包沒有供料或林務站已滿")
		give(inv,item,-quantity)
		station[field]=int(station[field])+quantity
		return ok("已裝入 %s ×%d"%[NAMES[item],quantity])
	var payout:Dictionary=station.items if action=="collect_forester" else {"charcoal":station.fuel,"sapling":station.saplings}
	var available:=false
	for id in payout:
		if int(payout[id])>0:available=true
		if int(inv.get(id,0))+int(payout[id])>1000000000:return fail("背包中的物品已達上限")
	if not available:return fail("目前沒有可取回的物品")
	for id in payout:
		if int(payout[id])>0:give(inv,id,int(payout[id]))
	if action=="collect_forester":station.items.clear()
	else:
		station.fuel=0
		station.saplings=0
	return ok("已領取林務產物" if action=="collect_forester" else "已取回林務供料")

func process_industry(token:String,k:String,action:String,kind:String) -> Dictionary:
	var device:Dictionary=state.objects.get(k,{})
	if device.get("type") in ["seed_maker","loom","glass_furnace"] and device.owner==token:return _processing_action(token,device,action,kind)
	if device.get("type","") not in LOGISTICS.PROCESSORS or device.owner!=token:
		return fail("只能使用自己的加工設備")
	var inv:Dictionary=state.players[token].inventory
	# T036 queue path: explicit queue actions, or any processing action on a
	# station that already carries `processing`. Untouched stations stay legacy.
	if action in ["queue_processing","cancel_processing_job"] or device.has("processing"):
		return _processing_action(token,device,action,kind)
	if action=="start_processing":
		if device.get("auto_enabled",false):return fail("先停用自動加工")
		if device.has("job"):return fail("設備正在加工")
		var recipe:Dictionary=INDUSTRY.PROCESS.get(kind,{})
		if recipe.get("station","")!=device.type:return fail("這台設備不能加工此物品")
		for item in recipe.ingredients:
			if int(inv.get(item,0))<int(recipe.ingredients[item]):return fail("加工材料不足")
		for item in recipe.ingredients:give(inv,item,-int(recipe.ingredients[item]))
		device.job={"kind":kind,"owner":token,"ready":float(state.time)+float(recipe.time),
			"ingredients":recipe.ingredients.duplicate(),"yield":int(recipe.yield)}
		return ok("開始加工："+NAMES[kind])
	if not device.has("job"):return fail("目前沒有加工工作")
	var job:Dictionary=device.job
	if job.get("auto",false):return fail("自動工作完成後請領取輸出")
	var payout:Dictionary=job.ingredients if action=="cancel_processing" else {job.kind:int(job.yield)}
	if action=="claim_processing" and float(state.time)<float(job.ready):return fail("加工尚未完成")
	for item in payout:
		if int(inv.get(item,0))+int(payout[item])>1000000000:return fail("背包中的物品已達上限")
	for item in payout:give(inv,item,int(payout[item]))
	device.erase("job")
	return ok("已退回加工材料" if action=="cancel_processing" else "已領取："+NAMES[job.kind])

## T036 queue-backed queue_processing / start_processing / claim_processing /
## cancel_processing / cancel_processing_job on an owned sawmill/charcoal kiln.
## Every path advances first and computes the whole pure transition before any
## write; act() additionally rolls back everything on failure or save failure.
## Results carry only job id and product kind (never owners or tokens).
func _processing_action(token: String, device: Dictionary, action: String, extra: String) -> Dictionary:
	var inv:Dictionary=state.players[token].inventory
	var now:=float(state.time)
	var catalog:=processing_recipes(str(device.type))
	if device.has("processing") and (device.has("job") or device.get("auto_enabled",false)):return fail(PROCESSING_MSG_CORRUPT)
	if action in ["queue_processing","start_processing"]:
		if device.get("auto_enabled",false):return fail("先停用自動加工")
		if not catalog.has(extra):return fail("這台設備不能加工此物品")
		var base:Dictionary
		if device.has("processing"):
			if not device.processing is Dictionary:return fail(PROCESSING_MSG_CORRUPT)
			var caught_up:Dictionary=COOKING_QUEUE.advance(device.processing,catalog,now)
			if not caught_up.ok:return fail(PROCESSING_MSG_CORRUPT)
			base=caught_up.state
		elif device.has("job"):
			# Lazy legacy import of the manual job, committed only with this enqueue.
			# Automatic jobs are never imported (they finish into the output buffer).
			if not device.job is Dictionary:return fail(PROCESSING_MSG_CORRUPT)
			if device.job.get("auto",false):return fail("自動工作完成後請領取輸出")
			if device.job.get("owner")!=device.owner:return fail(PROCESSING_MSG_CORRUPT)
			var import_id:=_queue_new_id({})
			if import_id=="":return fail(PROCESSING_MSG_CORRUPT)
			var imported:Dictionary=COOKING_QUEUE.import_legacy(device.job,catalog,now,import_id)
			if not imported.ok:return fail(PROCESSING_MSG_CORRUPT)
			base=imported.state
		else:
			base=COOKING_QUEUE.empty_state()
		var total:=_processing_total(base)
		if total>=COOKING_QUEUE.CAPACITY:return fail("加工排程已滿（最多 %d 份），請先領取或等候"%COOKING_QUEUE.CAPACITY)
		var recipe:Dictionary=catalog[extra]
		for item in recipe.ingredients:
			if int(inv.get(item,0))<int(recipe.ingredients[item]):return fail("加工材料不足：需要%s %d"%[str(NAMES.get(item,item)),int(recipe.ingredients[item])])
		var id:=_queue_new_id(base)
		if id=="":return fail(PROCESSING_MSG_CORRUPT)
		var queued:Dictionary=COOKING_QUEUE.enqueue(base,catalog,now,token,extra,id,inv)
		if not queued.ok:return fail("加工排程無法加入，這次沒有扣料")
		_cooking_commit_inventory(inv,queued.inventory)
		device.processing=queued.state
		device.erase("job")
		var product:=str(NAMES.get(extra,extra))
		var result:=_cooking_ok(("開始加工："+product) if queued.started else "已排入加工：%s（共 %d 份）"%[product,total+1],id,extra)
		result.started=bool(queued.started)
		return result
	if not device.has("processing"):return fail("目前沒有加工排程")
	if not device.processing is Dictionary:return fail(PROCESSING_MSG_CORRUPT)
	var advanced:Dictionary=COOKING_QUEUE.advance(device.processing,catalog,now)
	if not advanced.ok:return fail(PROCESSING_MSG_CORRUPT)
	var queue:Dictionary=advanced.state
	var active:Dictionary=queue.active
	var waiting:Array=queue.waiting
	var ready:Array=queue.ready
	if action=="claim_processing":
		if ready.is_empty():
			if active.is_empty():return fail("目前沒有完成的加工")
			return fail("加工尚未完成，還要 %d 秒"%ceili(float(active.finish)-now))
		var claimed:Dictionary=COOKING_QUEUE.claim(queue,catalog,now,inv)
		if not claimed.ok:return fail("背包中的物品已達上限" if str(claimed.message).contains("上限") else PROCESSING_MSG_CORRUPT)
		var kind:String=claimed.kind
		_cooking_commit_inventory(inv,claimed.inventory)
		device.processing=claimed.state
		var claim_result:=_cooking_ok("已領取：%s ×%d"%[str(NAMES.get(kind,kind)),int(claimed["yield"])],str(claimed.id),kind)
		claim_result["yield"]=int(claimed["yield"])
		return claim_result
	var target:Dictionary={}
	if action=="cancel_processing":
		if active.is_empty():return fail("目前沒有進行中的加工" if ready.is_empty() else "加工已完成，無法取消，請直接領取")
		target=active
	elif action=="cancel_processing_job":
		if not _is_lower_hex(extra,COOKING_QUEUE.ID_LENGTH):return fail("找不到這份加工")
		if not active.is_empty() and active.id==extra:target=active
		for entry in waiting:
			if entry.id==extra:target=entry
		if target.is_empty():
			for entry in ready:
				if entry.id==extra:return fail("加工已完成，無法取消，請直接領取")
			return fail("找不到這份加工")
	else:
		return fail("請選擇工具後再試一次")
	if target.owner!=token:return fail("只有投入材料的人可以取消")
	var cancelled:Dictionary=COOKING_QUEUE.cancel(queue,catalog,now,token,str(target.id),inv)
	if not cancelled.ok:return fail("背包中的物品已達上限，無法退回材料" if str(cancelled.message).contains("上限") else PROCESSING_MSG_CORRUPT)
	_cooking_commit_inventory(inv,cancelled.inventory)
	device.processing=cancelled.state
	var cancel_result:=_cooking_ok("已取消，加工材料完整退回",str(target.id),str(cancelled.kind))
	cancel_result.refunded=(cancelled.refunded as Dictionary).duplicate()
	return cancel_result

static func _processing_total(queue: Dictionary) -> int:
	return (0 if (queue.active as Dictionary).is_empty() else 1)+(queue.waiting as Array).size()+(queue.ready as Array).size()

func mine_action(token: String, action: String, p: Vector2i, extra: String, inv: Dictionary) -> Dictionary:
	var player: Dictionary = state.players[token]
	var depth := MINES.IDS.find(_region)
	var progress: Dictionary = state.mine_depths
	if action == "mine_travel":
		var destination := MINES.IDS.find(extra)
		var allowed := false
		# T067: the surface entry sign also lowers the hoist to opened landings
		# (B6/B10/B15) once Q07 repaired it; every floor from B6 has a hoist cage
		# back to the surface that always works.
		var by_lift := false
		if _region == REGIONS.JINGUASHI:
			by_lift = destination+1 in MINES.surface_landings(progress)
			allowed = p == MINES.ENTRY and state.picnic and (destination == 0 or by_lift)
			# Refused only because the hoist is still stuck: say what to do next.
			if not allowed and p == MINES.ENTRY and state.picnic and not MINES.hoist_ready(progress) and destination+1 in MINES.lift_targets(int(progress.unlocked)) and int(player.travel_epoch)<1000000000:
				return fail(HOIST_STUCK_MSG)
		elif depth >= 0:
			allowed = (p == MINES.UP and ((depth == 0 and extra == REGIONS.JINGUASHI) or (depth > 0 and destination == depth-1))) or (p == MINES.DOWN and destination == depth+1 and destination < int(progress.unlocked))
			allowed = allowed or (p == MINES.LIFT and depth+1 > MINES.SHALLOW_DEPTH and extra == REGIONS.JINGUASHI)
		if not allowed or int(player.travel_epoch)>=1000000000:return fail("此礦道尚未開放，或你離入口太遠。")
		var from := _region
		switch_region(extra)
		var entry := Vector2(27.5,19.5) if extra == REGIONS.JINGUASHI else (Vector2(MINES.LIFT)+Vector2(0.5,1.5) if by_lift else (Vector2(35.5,20.5) if depth > destination else REGIONS.spawn(extra)))
		var arrival := safe_arrival(entry)
		switch_region(from)
		if arrival == Vector2.ZERO:return fail("出口附近沒有安全落點。")
		player.region=extra
		_record_exploration(player,extra)
		player.x=arrival.x
		player.y=arrival.y
		player.travel_epoch=int(player.travel_epoch)+1
		for field in ["fishing","last_till","last_seed","last_harvest"]:player.erase(field)
		return ok("已抵達%s。" % REGIONS.label(extra))
	if action == HOIST_ACTION:
		# Q07: shared world progress, done once at the surface entry sign.
		if _region != REGIONS.JINGUASHI or p != MINES.ENTRY:return fail("請到金瓜石合作礦場的下坑路牌。")
		if not state.picnic:return fail("此礦道尚未開放，或你離入口太遠。")
		if int(progress.unlocked) < MINES.HOIST_DEPTH:return fail(HOIST_LOCKED_MSG)
		if MINES.hoist_ready(progress):return fail(HOIST_DONE_MSG)
		for item in MINES.HOIST_COST:
			if int(inv.get(item,0)) < int(MINES.HOIST_COST[item]):return fail(HOIST_SHORT_MSG)
		for item in MINES.HOIST_COST:give(inv,item,-int(MINES.HOIST_COST[item]))
		progress["hoist"] = true
		return ok(HOIST_OK_MSG)
	if depth < 0:return fail("請到合作礦場。")
	if action == "mine_rest":
		if p != MINES.REST:return fail("請到休息站。")
		player.mine_energy=100
		return ok("休息後恢復體力。")
	if action == "mine_commission":
		if p != MINES.SERVICE or depth != int(progress.unlocked)-1 or depth>=MINES.IDS.size()-1:return fail("這一層沒有待完成的工程。")
		if depth == 2 and int(progress.pumped)<24:
			return fail("以相連水泵、水管和水桶蓄水至少 24。")
		for item in MINES.COSTS[depth]:
			if int(inv.get(item,0))<int(MINES.COSTS[depth][item]):return fail("工程材料不足。")
		for item in MINES.COSTS[depth]:inv[item]-=MINES.COSTS[depth][item]
		progress.unlocked=int(progress.unlocked)+1
		return ok("已開通下一層礦道。")
	if p not in MINES.NODES or int(inv.get("reinforced_pick",0))<1:return fail("請帶強化石鎬到礦點。")
	if p==MINE_DRILL.NODE and MINE_DRILL.reserved(state.objects):return fail("這個礦點正由採掘機開採。")
	var ready: Dictionary = progress.ready.get(_region,{})
	if float(ready.get(key(p),0.0))>float(state.time):return fail("礦點正在整理。")
	var ore: String = MINES.ORES[depth]
	var quantity: int = MINES.YIELDS[depth]
	if int(inv.get(ore,0))>1000000000-quantity:return fail("背包已滿。")
	var rest := Vector2.ZERO
	var energy_cost := MINES.energy_cost(depth+1)
	if int(player.mine_energy)<=energy_cost:
		rest=safe_arrival(Vector2(MINES.REST)+Vector2(0.5,0.5))
		if rest==Vector2.ZERO:return fail("休息站目前無法抵達。")
	give(inv,ore,quantity)
	# B5 keeps its crystal sand; B6–B15 add the catalog finds (+1 each, skipped at the cap).
	var sand_note := ""
	for found:String in MINES.finds(depth+1):
		if int(inv.get(found,0)) >= 1000000000:continue
		give(inv,found,1)
		sand_note += "、%s +1" % NAMES[found]
	ready[key(p)]=float(state.time)+MINES.COOLDOWN
	progress.ready[_region]=ready
	player.mine_energy=maxi(0,int(player.mine_energy)-energy_cost)
	if rest!=Vector2.ZERO:
		player.x=rest.x
		player.y=rest.y
		player.mine_energy=100
		var result := ok("取得%s +%d%s，已回休息站。" % [NAMES[ore],quantity,sand_note])
		result.mine_exhausted=true
		return result
	return ok("取得%s +%d%s。" % [NAMES[ore],quantity,sand_note])

func lanyang_action(token: String, action: String, p: Vector2i, inventory: Dictionary) -> Dictionary:
	if _region != REGIONS.LANYANG:
		return fail("請先到蘭陽試作田。")
	var progress: Dictionary = state.lanyang_life
	if action == "lanyang_clear":
		if p not in LANYANG_LIFE.BLOCKAGES:
			return fail("請靠近有堵塞的水圳。")
		var location := key(p)
		if progress.cleared.has(location):
			return fail("這段水圳已清理。")
		progress.cleared[location] = true
		note_resident_participation(token,"canal")
		return ok("清開了水圳堵塞。")
	if p != LANYANG_LIFE.SERVICE:
		return fail("請到橋邊找星禾。")
	if action == "lanyang_donate":
		if progress.cleared.size() != LANYANG_LIFE.BLOCKAGES.size():
			return fail("先清完三處水圳堵塞。")
		if progress.repaired:
			return fail("水圳已修好。")
		var contributed := 0
		var remaining := 0
		for item in LANYANG_LIFE.REPAIR_COST:
			var need: int = LANYANG_LIFE.REPAIR_COST[item] - int(progress.donations[item])
			var count := mini(need,int(inventory.get(item,0)))
			if count > 0:
				inventory[item] -= count
				progress.donations[item] += count
				contributed += count
			remaining += need - count
		if contributed == 0:
			return fail("還需要木板、石材或樹脂。")
		note_resident_participation(token,"canal")
		progress.repaired = remaining == 0
		return ok("水圳修好了，河水泵進水加快，公共育苗也開放了。" if progress.repaired else "已交付這次帶來的修理材料。")
	if not progress.repaired:
		return fail("修好水圳後才能使用公共育苗。")
	if action == "nursery_start":
		if progress.jobs.has(token):
			return fail("你已有一批育苗，請先領取。")
		for item in LANYANG_LIFE.NURSERY_COST:
			if int(inventory.get(item,0)) < LANYANG_LIFE.NURSERY_COST[item]:
				return fail("育苗需要樹苗 1、纖維 4、木材 2。")
		for item in LANYANG_LIFE.NURSERY_COST:
			inventory[item] -= LANYANG_LIFE.NURSERY_COST[item]
		progress.jobs[token] = {"ready":float(state.time)+LANYANG_LIFE.NURSERY_TIME}
		return ok("星禾已開始育苗，約一分鐘後可領取。")
	var job: Dictionary = progress.jobs.get(token,{})
	if job.is_empty() or float(job.ready) > float(state.time):
		return fail("你目前沒有可領取的樹苗。")
	if int(inventory.get("sapling",0)) > 1000000000 - LANYANG_LIFE.NURSERY_YIELD:
		return fail("背包中的樹苗已達上限。")
	give(inventory,"sapling",LANYANG_LIFE.NURSERY_YIELD)
	progress.jobs.erase(token)
	return ok("領取了三棵小樹苗。")

static func bridge_fund_cost(snapshot:Dictionary)->int:
	var materials:Dictionary=snapshot.get("donations",{})
	return (30-int(materials.get("wood",0)))*int(FUND_MATERIAL_PRICES.wood)+(10-int(materials.get("stone",0)))*int(FUND_MATERIAL_PRICES.stone)

func note_resident_participation(token: String, event: String) -> void:
	var person: Dictionary=state.players[token]
	var events: Dictionary=person.get("resident_participation",{})
	events[event]=true
	person.resident_participation=events

func _finish_bridge()->void:
	state.board=true
	state.events.append("大家修好了公告板與河灣橋")

func _record_discovery(player:Dictionary,category:String,item_id:String) -> void:
	Collections.record(player,category,item_id)
	var field:=category+"_discoveries"
	if not player.has(field):player[field]={}
	var entry:={"region":_region,"day":int(WEATHER.day_index(float(state.time)))+1}
	if not player[field].has(item_id):player[field][item_id]=entry
	var island_field:="island_"+field
	if not state.has(island_field):state[island_field]={}
	if not state[island_field].has(item_id):
		var first:=entry.duplicate()
		first.name=player.name
		state[island_field][item_id]=first

func _harvest_plot(token:String,player:Dictionary,crop:Dictionary,tile_key:String) -> int:
	if greenhouse_covers(tile_key) and not crop_grows_in_season(crop.kind,_region,cell(tile_key),float(state.time)):
		if state.roofs[tile_key].owner==token and crop.get("owner","")==token:
			player.greenhouse_cross_season_crop=crop.kind
	var count:int=CROPS[crop.kind].yield
	give(player.inventory,crop.kind,count)
	_record_discovery(player,"crops",crop.kind)
	CHAPTER_ONE.record_harvest(state,token,crop.kind,count)
	player.harvests+=1
	crop["remaining"]=maxi(0,int(crop.get("remaining",1))-1)
	if int(crop.remaining)==0:
		crop.kind=""
		crop.growth=0.0
	else:crop.growth=regrow_start(str(crop.kind))
	crop.wet=false
	return count

static func give(inv:Dictionary,item:String,amount:int) -> void:
	inv[item]=int(inv.get(item,0))+amount

## T014: units a CHEST_MOVES action moves out of a source stack of `have`.
## deposit/withdraw -> 1, *_half -> ceil(have/2) (a single item still moves),
## *_all -> have. 0 when there is nothing to move.
static func chest_move_amount(action:String,have:int) -> int:
	if have<=0:return 0
	if action.ends_with("_all"):return have
	if action.ends_with("_half"):return have-(have>>1)
	return 1

static func ok(message:String) -> Dictionary:
	return {"ok":true,"message":message}

static func fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}

func save() -> bool:
	if _region != REGIONS.HOME:
		save_error = "Cannot save while a regional projection is active."
		return false
	if save_path.is_empty():return true
	var file:=FileAccess.open(save_path+".tmp",FileAccess.WRITE)
	if file==null:
		save_error="Cannot open temporary save: %s"%FileAccess.get_open_error()
		return false
	file.store_string(JSON.stringify(state))
	file.flush()
	var err:=file.get_error()
	file.close()
	if err!=OK:
		save_error="Cannot flush save: %s"%err
		return false
	# After recovery, keep the known-good backup and retain the damaged original.
	# Normal rotation would otherwise replace the good backup with bad data.
	if recovered_from_backup:
		var quarantined:=""
		if FileAccess.file_exists(save_path):
			quarantined=save_path+".rejected-%d"%Time.get_ticks_usec()
			if DirAccess.rename_absolute(save_path,quarantined)!=OK:return false
		if DirAccess.rename_absolute(save_path+".tmp",save_path)!=OK:
			if not quarantined.is_empty():DirAccess.rename_absolute(quarantined,save_path)
			return false
		rejected_path=quarantined
		recovered_from_backup=false
		return true
	if FileAccess.file_exists(save_path):
		if FileAccess.file_exists(save_path+".bak"):DirAccess.remove_absolute(save_path+".bak")
		if DirAccess.rename_absolute(save_path,save_path+".bak")!=OK:return false
	if DirAccess.rename_absolute(save_path+".tmp",save_path)!=OK:
		if FileAccess.file_exists(save_path+".bak"):DirAccess.rename_absolute(save_path+".bak",save_path)
		return false
	return true

func load_world(path:String) -> bool:
	save_path=path
	if not FileAccess.file_exists(path):
		if FileAccess.file_exists(path+".bak"):
			recovered_from_backup=_load_file(path+".bak")
			return recovered_from_backup
		return true
	if _load_file(path):recovered_from_backup=false;return true
	if FileAccess.file_exists(path+".bak"):
		recovered_from_backup=_load_file(path+".bak")
		return recovered_from_backup
	return false

func _load_file(path:String) -> bool:
	var parser:=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK:return false
	var parsed=parser.data
	if not parsed is Dictionary:return false
	if not preload("res://scripts/save_schema.gd").validate(parsed,CROPS,BUILD,RECIPES,SIZE,TREE_TIME):return false
	state=parsed
	_region=REGIONS.HOME
	# Monotonic ticks only bind records captured by THIS process and world.
	_undo_ticks_at={}
	_undo_used={}
	return true
