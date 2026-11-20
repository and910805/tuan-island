extends RefCounted
const VIEW_PROJECTION=preload("res://scripts/view_projection.gd")
const CHICKEN_CUDDLE=preload("res://scripts/chicken_cuddle.gd")
const CHICKEN_FEED_FOLLOW=preload("res://scripts/chicken_feed_follow.gd")
const COW_CARE=preload("res://scripts/cow_care.gd")
const MUSHROOM_MAIL=preload("res://scripts/mushroom_mail.gd")
const ISLAND_NOTES=preload("res://scripts/island_notes.gd")
const DOCK_REPAIRS := [{"plank":12,"stone":8},{"plank":8,"fiber":10,"copper_joint":2}]
const OUTLYING_COMMISSIONS=preload("res://scripts/outlying_commissions.gd")
const FOREST_MUSHROOM=preload("res://scripts/forest_mushroom_commission.gd")
const ISLAND_STORY_RECAP=preload("res://scripts/island_story_recap.gd")
const BUILD_STYLES = preload("res://scripts/build_style_catalog.gd")
const WALL_FIXTURES = preload("res://scripts/wall_fixtures.gd")
const BARK_FRAME = preload("res://scripts/bark_frame.gd")
const POSTCARDS = preload("res://scripts/travel_postcards.gd")
const OAR_SIGN = preload("res://scripts/oar_sign.gd")
const ROOF_FIXTURES = preload("res://scripts/roof_fixtures.gd")
const TERRACOTTA_ROOF = preload("res://scripts/terracotta_roof.gd")
const NURSERY_BOX = preload("res://scripts/nursery_box.gd")
const ITEM_CATALOG = preload("res://scripts/item_catalog.gd")
const WELCOME_SIGN = preload("res://scripts/welcome_sign.gd")
const INN_TEA_TABLE:="inn_tea_table"
const INN_TEA_ITEM:="mist_tea_brew"
const GINGER_TEA:="ginger_tea"
const WARM_SPRINGS=preload("res://scripts/warm_springs.gd")
const TEA_HOUSE_INTERIOR=preload("res://scripts/tea_house_interior.gd")
const POTTERY_WORKSHOP_INTERIOR=preload("res://scripts/pottery_workshop_interior.gd")
const MEAL_BUFF=preload("res://scripts/meal_buff.gd")
const WANGAN_MEMORY=preload("res://scripts/wangan_memory.gd")
const WANGAN_COAST=preload("res://scripts/wangan_coast.gd")
const INN_TEA_ITEMS:=[INN_TEA_ITEM,GINGER_TEA]
const INN_TEA_SLOTS:=2
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
const GUARDIAN=preload("res://scripts/sleepy_stone_guardian.gd")
const GUARDIAN_FIELD:="sleepy_guardian"
const GUARDIAN_TRIAL=preload("res://scripts/stone_guardian_trial.gd")
## 打瞌睡石像: half-entered bell phrase per player token. Host memory only, never saved
## or broadcast; a reload simply restarts the current phrase.
var _guardian_entered:Dictionary={}
var _guardian_trials:Dictionary={}
## 害羞菇 (B2 east nook, optional): per-player record field and host-memory quiet-wait anchors.
const SHY=preload("res://scripts/shy_mushroom.gd")
const SHY_FIELD:="shy_mushroom"
var _shy_watch:Dictionary={}
const SHY_SPORES=preload("res://scripts/shy_spores.gd")
var _shy_spores:Dictionary={}
const CRAB=preload("res://scripts/stone_shelled_crab.gd")
const CRAB_FIELD:="stone_crab"
const PORTER=preload("res://scripts/lost_porter_mouse.gd")
const MEADOW=preload("res://scripts/meadow_guardian.gd")
const MEADOW_ADVENTURE=preload("res://scripts/meadow_adventure.gd")
var _meadow_round:Dictionary={}
## Adventure-route wait cycle ({"open_at":world_seconds}); host memory only, never saved.
var _crab_watch:Dictionary={}
const TEA_CERAMICS=preload("res://scripts/tea_ceramics.gd")
const MINE_FREIGHT=preload("res://scripts/mine_freight.gd")
const BOX_CAPACITY=preload("res://scripts/box_capacity.gd")
const MINES=preload("res://scripts/mine_depths.gd")
const JINGUASHI=preload("res://scripts/jinguashi.gd")
const HISTORY_MEMORY=preload("res://scripts/history_memory.gd")
const LANYANG_LIFE=preload("res://scripts/lanyang_life.gd")
const TRANSIT=preload("res://scripts/transit.gd")
const REGIONS=preload("res://scripts/regions.gd")
const PARTY_CART=REGIONS.Cart
const VILLAGE_LAYOUT=preload("res://scripts/village_layout.gd")
const COMMUNITY=preload("res://scripts/community.gd")
const COIN_CAP_MSG:="鈴幣已達上限，先花掉一些再來。"
const FUND_DONATIONS:=["10","25","50"]
const FUND_MATERIAL_PRICES:={"wood":5,"stone":8}
const ORDER_CATALOG=preload("res://scripts/order_catalog.gd")
const ORDER_BOARDS:={
	"village":{"region":"home","cell":Vector2i(40,29),"title":"公告板的生活訂單","location":"風鈴渡口・公告板"},
	"dock":{"region":"home","cell":WANGAN_COAST.DOCK_ORDERS,"title":"望安碼頭訂單","location":"望安碼頭・訂單牌"},
	"lanyang":{"region":"lanyang","cell":LANYANG_LIFE.SERVICE,"title":"蘭陽水圳訂單","location":"蘭陽水圳・木橋旁的星禾"},
}
const AnimalCollector=preload("res://scripts/animal_collector.gd")
const Rabbit=preload("res://scripts/companion_rabbit.gd")
const Cat=preload("res://scripts/companion_cat.gd")
const Dog=preload("res://scripts/companion_dog.gd")
const Fox=preload("res://scripts/companion_fox.gd")
const Hedgehog=preload("res://scripts/courtyard_hedgehog.gd")
const Squirrel=preload("res://scripts/woodland_squirrel.gd")
const Seal=preload("res://scripts/shore_seal.gd")
const Deer=preload("res://scripts/windbell_deer.gd")
const LIVESTOCK=preload("res://scripts/livestock.gd")
const CHAPTER_ONE=preload("res://scripts/chapter_one.gd")
const MILL_RESTORATION=preload("res://scripts/mill_restoration.gd")
const SHIPPING=preload("res://scripts/shipping.gd")
const Village=preload("res://scripts/village.gd")
const RESIDENT_BOND=preload("res://scripts/resident_bond.gd")
const ARU_BENCH=preload("res://scripts/aru_bench_rest.gd")
const RESIDENT_GOALS=preload("res://scripts/resident_goals.gd")
const MARKET=preload("res://scripts/market_stall.gd")
const MARKET_DECOR=preload("res://scripts/market_decor.gd")
const XIAOLI_SHOP=preload("res://scripts/xiaoli_shop.gd")
const SPRING_GARDEN=preload("res://scripts/spring_garden_day.gd")
const SEA_BREEZE_FAIR=preload("res://scripts/sea_breeze_fair.gd")
const AUTUMN_FEAST=preload("res://scripts/autumn_feast.gd")
const LANTERN_STROLL=preload("res://scripts/lantern_stroll.gd")
const WARM_LANTERN_NIGHT=preload("res://scripts/warm_lantern_night.gd")
const BEACH_TREASURE=preload("res://scripts/beach_treasure.gd")
const LOST_CHICKS=preload("res://scripts/lost_chicks.gd")
const COOKING_RELAY=preload("res://scripts/cooking_relay.gd")
const SUMMER_MARKET=preload("res://scripts/summer_market.gd") # C12 D14 夏季市集試吃（渡口市集攤位）
const HARVEST=preload("res://scripts/harvest_relay.gd")
const FISH_MEET=preload("res://scripts/fishing_meet.gd")
const SHOWCASE=preload("res://scripts/showcase.gd")
const SOUVENIR=preload("res://scripts/souvenir_exchange.gd")
const TABLE_WARMER=preload("res://scripts/table_warmer.gd")
const MILU_SUPPER=preload("res://scripts/milu_supper.gd")
const LANYANG_REVISIT=preload("res://scripts/lanyang_revisit.gd")
const JINGUASHI_REVISIT=preload("res://scripts/jinguashi_revisit.gd")
const GOLD_PANNING=preload("res://scripts/gold_panning.gd")
const ORE_ROUTE=preload("res://scripts/ore_route.gd")
const BOBO_EMPTY_CART=preload("res://scripts/bobo_empty_cart.gd") # T066 N03-4 最後一趟空車
const TEA_REVISIT=preload("res://scripts/tea_revisit.gd")
const TEA_SERVICE=preload("res://scripts/tea_service.gd")
const SALT_REVISIT=preload("res://scripts/salt_revisit.gd")
const SALT_BRINE=preload("res://scripts/salt_brine.gd")
const MEMORY_EXHIBIT=preload("res://scripts/memory_exhibit.gd")
const Festival=preload("res://scripts/festival.gd")
const LOGISTICS=preload("res://scripts/logistics.gd")
const TILLER=preload("res://scripts/tiller.gd")
const PUBLIC_TILLER=preload("res://scripts/public_tiller.gd")
const SEEDER=preload("res://scripts/seeder.gd")
const HARVESTER=preload("res://scripts/harvester.gd")
const FORESTRY=preload("res://scripts/forestry.gd")
const WOODLAND=preload("res://scripts/woodland_stock.gd")
const INDUSTRY=preload("res://scripts/industry.gd")
const STONE_WORKSHOP=preload("res://scripts/stone_workshop.gd")
const PAVILION=preload("res://scripts/imperfect_tea_pavilion.gd")
const Collections=preload("res://scripts/collections.gd")
const FishingTracking=preload("res://scripts/fishing_tracking.gd")
const AUTO_ROOF_PLAN=preload("res://scripts/auto_roof_plan.gd")
const EDGE_FOOT_SWEEP=preload("res://scripts/edge_foot_sweep.gd")
const EDGE_CONSTRUCTION=preload("res://scripts/edge_construction.gd")
const EDGE_GRID=preload("res://scripts/edge_grid.gd")
const ROOM_ENCLOSURE=preload("res://scripts/room_enclosure.gd")
const GREENHOUSE_GLASS=preload("res://scripts/greenhouse_glass.gd")
const MAX_OUTDOOR_VISIT_TILES:=25
const AUTO_ROOF_SETTLEMENT=preload("res://scripts/auto_roof_settlement.gd")
const CONSTRUCTION_UNDO=preload("res://scripts/construction_undo.gd")
const CONSTRUCTION_HISTORY=preload("res://scripts/construction_history.gd")
const BLUEPRINT_DESIGN=preload("res://scripts/blueprint_design.gd")
const COOKING_QUEUE=preload("res://scripts/cooking_queue.gd")
const MATERIAL_SOURCES=preload("res://scripts/material_sources.gd")
const SAVE_SCHEMA=preload("res://scripts/save_schema.gd")
const PUBLIC_KITCHEN=preload("res://scripts/public_kitchen.gd")
const KITCHEN_STOVE=preload("res://scripts/kitchen_stove.gd")
const WEATHER=preload("res://scripts/weather.gd")
## C12/D04: a little flour at Xiaoli's stall before the mill. Server-owned numbers (the client only
## sends extra="flour"): 4 per account per world day, 64 coins each. 64 is above the instant bread sale
## (OTHER_SALES.bread = 48) and above the best market-stall bread price (48 x1.3 rounded up = 63), so
## buying flour to cook and sell bread can never turn a profit. Flour has no sale price: never sold back.
const FLOUR_ITEM:="flour"
const FLOUR_PRICE:=SAVE_SCHEMA.FLOUR_STALL_PRICE
const FLOUR_DAILY:=SAVE_SCHEMA.FLOUR_STALL_DAILY
## 內容設定集 §11 / D12: a little sugar at Xiaoli's stall before the winter beet unlocks. Same pattern as
## flour: server-owned, 2 per account per world day, 72 coins each. 72 is above one 霜糖甜菜 (66, and the
## 熬製甜菜糖 recipe turns 2 beets into 2 sugar), so buying is never cheaper than farming; it is also above
## the 田尾 market sugar (40, separate cap of 2), which stays the cheaper source for flower-chapter players.
## garden_cookie (4 x 36 = 144) costs flour 64 + sugar 72 + herb >= 24, so stall ingredients cannot profit.
## Sugar still has no sale price: never sold back.
const SUGAR_ITEM:="sugar"
const SUGAR_PRICE:=SAVE_SCHEMA.SUGAR_STALL_PRICE
const SUGAR_DAILY:=SAVE_SCHEMA.SUGAR_STALL_DAILY
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
const LEGACY_GLASS_FURNACE_COST := {"stone":12,"ochre_earth":4,"copper_joint":2}
const LEGACY_LOOM_COST := {"plank":8,"fiber":4,"copper_joint":1}
const LEGACY_SEED_MAKER_COST := {"plank":8,"stone":6,"copper_joint":2}
const LEGACY_JAM_POT_COST := {"stone":8,"copper_joint":1}
## C13: a mill placed from a kit (no `mill_part`) is a 1x1 forever: it is built from / refunds one mill_kit.
## The kit item itself stays (NAMES/ITEMS/backpack) but can no longer be crafted.
const LEGACY_MILL_COST := INDUSTRY.LEGACY_MILL_COST
## Windows built before 木窗 carry no discriminator and refund their original 6 wood + 1 stone.
## New windows carry `wood_window=true` and refund the current BUILD.window cost.
const WOOD_WINDOW_FIELD := "wood_window"
const LEGACY_WINDOW_COST := {"wood":6,"stone":1}
const KIT_SPRINKLER_COST := {"name":"小型灑水器","sprinkler_kit":1}
const LEGACY_MEDIUM_SPRINKLER_COST := {"sprinkler_kit":1,"copper_joint":3,"plank":4}
const UNDO_SOLID := ["ore_display", "wall", "window", "chest", "private_chest", "supply_box", "bench", INDUSTRY.STONE_WORKBENCH, "bed", INDUSTRY.CEDAR_BED, INDUSTRY.MUSHROOM_STOOL, INDUSTRY.MUSHROOM_TABLE, INDUSTRY.BAMBOO_TEA_TABLE, INDUSTRY.TEA_DISPLAY_CABINET, INDUSTRY.TEA_SNACK_SHELF, INDUSTRY.HOLLOW_BED, INDUSTRY.ACORN_CABINET, "inn_quilt_bed", "inn_stone_footbath", "table", INDUSTRY.ROUNDED_TABLE, INDUSTRY.GRID_BOOKCASE, "stove",INDUSTRY.KITCHEN_STOVE,"long_bench","master_bench","spring_stone_bench",RESIDENT_GOALS.COTTON_SOFA,RESIDENT_GOALS.BAMBOO_BENCH,"small_smelter","sofa","planter","sketch_easel","guest_wardrobe","inn_lattice_wardrobe",RESIDENT_GOALS.COAST_WARDROBE,RESIDENT_GOALS.FOREST_WARDROBE,"inn_fabric_screen","wood_mailbox",INDUSTRY.MUSHROOM_POST,INDUSTRY.QUIET_BIRDHOUSE,"rope_rack",POSTCARDS.RACK,"towel_rack","inn_tea_table","inn_luggage_rack","flower_pot","greenhouse_rack","garden_basin",RESIDENT_GOALS.GARDEN_CHAIR,"crop_observation_desk",INDUSTRY.LEAF_DESK,INDUSTRY.SEED_CABINET,NURSERY_BOX.KIND,INDUSTRY.AQUARIUM,INDUSTRY.COAST_FISH_COUNTER,INDUSTRY.COAST_REGISTER,INDUSTRY.COAST_CART,INDUSTRY.BEACH_CHAIR,INDUSTRY.RIVERSIDE_SCREEN,INDUSTRY.BAMBOO_LOUNGER,INDUSTRY.SHELL_TABLE,INDUSTRY.GLASS_FLOWER_TABLE,INDUSTRY.VINE_ARCH,INDUSTRY.FOREST_ARCH,INDUSTRY.POT_RACK,"master_flower_bed","fish_display","author_sign","author_shelf","expedition_tent","sprinkler","medium_sprinkler","large_sprinkler","water_tank","water_tower","water_pump","waterworks","mine_drill","sawmill","charcoal_kiln","forester","mill","seed_maker","loom","glass_furnace","small_smelter","jam_pot","clay_kiln","dye_table","assembly_table","animal_collector"]
## Q05 bakery: the flour mill kit and the mill itself unlock only once the
## shared public kitchen has opened (state.public_kitchen.opened). Every route
## (plain/sourced craft, build, blueprint simulation, undo restore) uses this.
const KITCHEN_GATED := ["mill_kit","mill"]
const MILL_LOCKED_MSG := "麵粉磨坊要等公共廚房開張後才能製作或建造：先在共用餐桌登記公共廚房，再和大家備齊蘿蔔湯 4、麵包 2、菜園沙拉 2。"
## Chapter 3 Tianwei: only nursery-bed care (hoe/seed/water/harvest, remove of
## own empty beds) and the FlowerNursery stations are open there.
const CHEST_MOVES := TRANSACTION_LEDGER.CHEST_MOVES
const CHEST_EXACT_MOVES := TRANSACTION_LEDGER.CHEST_EXACT_MOVES
const FLOWER_REJECTED := ["build","build_area","move_object","plant_tree","axe","pick","till_area","seed_area","harvest_area","craft","cook","queue_cook","claim_cook","cancel_cook","cancel_queued_cook","fish_start","fish_catch","door","prepare_material_box"] + CHEST_MOVES
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
const AUTO_ROOF_BUILDS := ["floor","stone_floor","wall","window","door"]
const AUTO_ROOF_AREAS := ["floor","stone_floor"]
const AUTO_ROOF_REMOVES := ["floor","stone_floor","wall","window","door"]

const SIZE := Vector2i(80, 60)
const MOVE_TILES_PER_SECOND:=3.6
const SPAWN := Vector2(39.5, 33.5)
const SEAWEED_CELL := Vector2i(54,53)
const SEAWEED_POINT := "shore_seaweed"
const RICE_BALL_ENERGY := 25
const ROPE_FIBER_COST := 5
const SEAWEED_REGROW_SECONDS := 60.0
const TREE_TIME := 180.0
const HARDWOOD_YIELD:=2
const COPPER_CELL := Vector2i(54,24)
const SPRINKLER_INTERVAL := 8.0
const SPRINKLER_CAPACITY := INDUSTRY.SPRINKLER_CAPACITIES.sprinkler
const SPRINKLER_LIMIT := INDUSTRY.SPRINKLER_LIMIT
const CHICKEN_CELL := AnimalCollector.CHICKEN_CELL
const CHICKEN_EGG_SECONDS := CHICKEN_FEED_FOLLOW.EGG_SECONDS
const EGG_BASKET_CAPACITY := SAVE_SCHEMA.EGG_BASKET_CAPACITY
const CRAFT := {
	INDUSTRY.TABLE_VASE:{"name":"桌邊花瓶・風鈴香草","ingredients":{"clay":4,"chime_herb":1},"yield":1},
	INDUSTRY.TEA_SET:{"name":"小陶茶具","ingredients":INDUSTRY.TEA_SET_COST,"yield":1},
	"egg_basket":{"name":"收集籃","ingredients":{"wood":8,"fiber":6},"yield":1},
	"gold_sample":{"name":"金工收藏樣本","ingredients":{"gold_ore":3},"yield":1},
	"reinforced_pick":{"name":"強化石鎬","ingredients":{"wood":6,"stone":4,"fiber":2},"yield":1},
	"copper_pick":{"name":"銅鎬","ingredients":{"reinforced_pick":1,"copper_ingot":4,"resin":1},"yield":1},
	"iron_pick":{"name":"鐵鎬","ingredients":{"copper_pick":1,"iron_ingot":4,"plank":2},"yield":1},
	"precision_pick":{"name":"精製鎬","ingredients":{"iron_pick":1,"iron_ingot":2,"vein_quartz":2},"yield":1},
	"copper_axe":{"name":"銅斧","ingredients":{"copper_ingot":4,"wood":3,"fiber":2},"yield":1},
	"iron_axe":{"name":"鐵斧","ingredients":{"copper_axe":1,"iron_ingot":4,"hardwood":2},"yield":1},
	"precision_axe":{"name":"精製斧","ingredients":{"iron_axe":1,"iron_ingot":2,"vein_quartz":2},"yield":1},
	"copper_hoe":{"name":"銅鋤","ingredients":{"copper_ingot":3,"wood":3,"fiber":2},"yield":1},
	"iron_hoe":{"name":"鐵鋤","ingredients":{"copper_hoe":1,"iron_ingot":3,"plank":2},"yield":1},
	"precision_hoe":{"name":"精製鋤","ingredients":{"iron_hoe":1,"iron_ingot":2,"vein_quartz":2},"yield":1},
	"copper_can":{"name":"銅澆水壺","ingredients":{"copper_ingot":3,"resin":1,"fiber":2},"yield":1},
	"iron_can":{"name":"鐵澆水壺","ingredients":{"copper_can":1,"iron_ingot":3,"plank":2},"yield":1},
	"precision_can":{"name":"精製澆水壺","ingredients":{"iron_can":1,"iron_ingot":2,"vein_quartz":2},"yield":1},
	"copper_rod":{"name":"銅釣竿","ingredients":{"copper_ingot":3,"wood":3,"fiber":2},"yield":1},
	"iron_rod":{"name":"鐵釣竿","ingredients":{"copper_rod":1,"iron_ingot":3,"plank":2},"yield":1},
	"precision_rod":{"name":"精製釣竿","ingredients":{"iron_rod":1,"iron_ingot":2,"vein_quartz":2},"yield":1},
	"copper_seed_pouch":{"name":"銅扣撒種袋","ingredients":{"copper_ingot":3,"fiber":6,"resin":1},"yield":1},
	"iron_seed_pouch":{"name":"鐵扣撒種袋","ingredients":{"copper_seed_pouch":1,"iron_ingot":3,"plank":2},"yield":1},
	"precision_seed_pouch":{"name":"精製撒種袋","ingredients":{"iron_seed_pouch":1,"iron_ingot":2,"vein_quartz":2},"yield":1},
	"copper_sickle":{"name":"銅採收鐮","ingredients":{"copper_ingot":3,"wood":3,"fiber":2},"yield":1},
	"iron_sickle":{"name":"鐵採收鐮","ingredients":{"copper_sickle":1,"iron_ingot":3,"plank":2},"yield":1},
	"precision_sickle":{"name":"精製採收鐮","ingredients":{"iron_sickle":1,"iron_ingot":2,"vein_quartz":2},"yield":1},
	"shell_bottle_scallop":{"name":"玻璃貝殼瓶・白扇貝","ingredients":INDUSTRY.SHELL_BOTTLE_COST,"yield":1},
	"shell_bottle_conch":{"name":"玻璃貝殼瓶・粉海螺","ingredients":INDUSTRY.SHELL_BOTTLE_COST,"yield":1},
	"shell_bottle_tide":{"name":"玻璃貝殼瓶・青潮貝","ingredients":INDUSTRY.SHELL_BOTTLE_COST,"yield":1},
	"mine_drill_kit":{"name":"礦脈採掘機","ingredients":MINE_DRILL.COST,"yield":1},
	"waterworks_kit":{"name":"水力加工台","ingredients":WATERWORKS.COST,"yield":1},
	"supply_box_kit":{"name":"便攜補給箱","ingredients":{"plank":4,"fiber":2},"yield":1},
	"glass":{"name":"溫室玻璃","ingredients":{"crystal_sand":2,"charcoal":1},"yield":2},
	"copper_joint":{"name":"銅接頭","ingredients":{"copper_ore":2,"wood":1},"yield":1},
	"woodwork_parts":{"name":"木工零件","ingredients":{"plank":2,"hardwood":1},"yield":2},
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
const WORKSHOP_LEVEL := 6
const BASIC_BUILD_AREA := 25
const CRAFTING_LEVEL_THRESHOLDS := [0,4,10,20,35,55,80,110,145,185]
const GATHERING_LEVEL_THRESHOLDS := [0,4,10,20,35,55,80,110,145,185]
const SAPLING_RECOVERY_LEVEL := 3
const RESOURCE_MAP_LEVEL := 6
const FARMING_LEVEL_THRESHOLDS := [0,4,10,20,35,55,80,110,145,185]
const SEED_MAKER_LEVEL := 3
const MEDIUM_SPRINKLER_LEVEL := 6
const LARGE_SPRINKLER_LEVEL := 8
const MASTER_FARMING_LEVEL := 10
const SEED_MAKER := preload("res://scripts/seed_maker.gd")
const CROP_CATALOG := preload("res://scripts/crop_catalog.gd")
const CROPS := CROP_CATALOG.CROPS
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
const STAR_GARDEN_LAMP:="star_garden_lamp"
const BUILD := {
	"loom":{"name":"織布機","wood":20,"fiber":10,"woodwork_parts":2},
	"animal_collector":{"name":"動物自動收集器","animal_collector_kit":1},
	"assembly_table":{"name":"裝配桌","hardwood":20,"iron_ingot":6,"woodwork_parts":4},
	"dye_table":{"name":"染色桌","wood":12,"clay":6},
	"clay_kiln":{"name":"陶窯","stone":30,"clay":10},
	"jam_pot":{"name":"果醬鍋","clay":10,"copper_ingot":4},
	# T067 Q07 reward: blueprint unlocked by repairing the Jinguashi hoist.
	"small_smelter":{"name":"小熔爐","stone":25,"copper_ore":5},
	"glass_furnace":{"name":"玻璃爐","stone":25,"iron_ingot":6},
	"seed_maker":{"name":"種子機","wood":15,"copper_ingot":4,"woodwork_parts":2},
	"ore_display":{"name":"礦樣展示架","wood":4,"gold_sample":1},
	"floor": {"name": "木地板", "wood": 2},
	# C09: walkable 1x1 ground; a structural floor for stone houses (see room_enclosure.gd FLOOR_KINDS).
	"stone_floor": {"name": "石地板", "stone": 2},
	"wall": {"name": "木牆", "wood": 3},
	"path": {"name": "石板路", "stone": 2},
	"spring_pebble_path": {"name":"泉邊卵石路","stone":2,"clay":1},
	"chest": {"name": "共用木箱", "wood": 20},
	"bench": {"name": "木工台", "wood": 20, "stone": 5},
	# C11 石工台: 2x1, unlocked by the Q03 board flag (state.board), no mine metal.
	INDUSTRY.STONE_WORKBENCH:{"name":"石工台","stone":20,"wood":8},
	"bed": {"name": "小床", "wood": 15, "fiber": 10},
	INDUSTRY.CEDAR_BED:{"name":"原木小床","wood":15,"fiber":10},
	INDUSTRY.MUSHROOM_STOOL:{"name":"小菇矮凳","wood":6,"star_mushroom":1},
	INDUSTRY.LEAF_MAT:{"name":"葉片地墊","fiber":12,"chime_herb":3},
	INDUSTRY.BRAIDED_RUG:{"name":"編繩圓地墊","fiber":12,"cotton_cloth":2},
	INDUSTRY.SPORE_LAMP:{"name":"孢子小夜燈","wood":4,"glass":1,"star_mushroom":2},
	INDUSTRY.ACORN_CABINET:{"name":"橡果收納櫃","hardwood":16,"fiber":4},
	INDUSTRY.HEDGEHOG_BASKET:{"name":"刺蝟午睡籃","wood":6,"fiber":10},
	INDUSTRY.MUSHROOM_TABLE:{"name":"傘帽圓桌","hardwood":12,"star_mushroom":3},
	INDUSTRY.BAMBOO_TEA_TABLE:{"name":"低腳竹茶桌","bamboo":12,"wood":4},
	INDUSTRY.TEA_DISPLAY_CABINET:{"name":"茶葉展示櫃","bamboo":12,"glass":4},
	INDUSTRY.PAPER_TEA_LAMP:{"name":"紙罩茶燈","bamboo":4,"cotton_cloth":2,"copper_ingot":1},
	INDUSTRY.HOLLOW_BED:{"name":"樹洞小床","hardwood":18,"cotton_cloth":5,"fiber":8},
	"inn_quilt_bed":{"name":"厚被旅舍床","hardwood":12,"cotton_cloth":6,"wool_cloth":3},
	"inn_stone_footbath":{"name":"暖石泡腳池","stone":24,"clay":8,"hardwood":8},
	"lamp": {"name": "暖木落地燈", "wood": 5, "stone": 2},
	"door": {"name": "木門", "wood": 6, "fiber": 2},
	"window": {"name": "木窗", "wood": 4, "glass": 1},
	"greenhouse_roof":{"name":"溫室玻璃棚","glass":2,"copper_joint":1},
	GREENHOUSE_GLASS.XINGHE_ROOF:{"name":"星禾的溫室頂","glass":2,"copper_ingot":1},
	"roof": {"name": "草編屋頂", "wood": 1, "fiber": 3},
	# C16: laid with kiln-fired tiles only, so it needs no unlock beyond a working clay kiln.
	TERRACOTTA_ROOF.KIND:{"name":TERRACOTTA_ROOF.NAME,TERRACOTTA_ROOF.TILE:1},
	"table": {"name": "小木桌", "wood": 12},
	INDUSTRY.ROUNDED_TABLE:{"name":"圓角木桌","wood":12},
	INDUSTRY.GRID_BOOKCASE:{"name":"格子書櫃","wood":16,"fiber":4},
	INDUSTRY.WOOD_CHAIR: {"name": "矮背木椅", "wood": 6},
	INDUSTRY.INDIGO_CUSHION:{"name":"靛藍坐墊","cotton_cloth":3,"blue_dye":1},
	"stove": {"name": "小石灶", "wood": 12, "stone": 15},
	# C12 公共廚房灶台: separate 2x2 type; the 小石灶 above keeps its id and cost.
	INDUSTRY.KITCHEN_STOVE:{"name":"公共廚房灶台","stone":20,"wood":12,"clay":5},
	"supply_box":{"name":"便攜補給箱","supply_box_kit":1},
	"private_chest": {"name": "私人木箱", "wood": 20},
	"long_bench":{"name":"雙人長椅","wood":14,"fiber":4},
	"master_bench":{"name":"師父的長椅","wood":14,"hardwood":4},
	"spring_stone_bench":{"name":"石邊長凳","stone":8,"hardwood":8},
	"author_sign":{"name":"工匠署名牌","plank":3,"fiber":1},
	"expedition_tent":{"name":"探險紀念帳篷","plank":6,"wool_cloth":2},
	"author_shelf":{"name":"工匠展示架","plank":6,"glass":1},
	"fish_display":{"name":"島岸魚譜展示櫃","glass":2,"plank":6},
	"master_flower_bed":{"name":"豐收花圃","plank":4,"stone":2,"fiber":2},
	"greenhouse_rack":{"name":"溫室花架","plank":4,"fiber":2},
	"garden_basin":{"name":"園藝水盆","clay":8,"stone":4},
	STAR_GARDEN_LAMP:{"name":"星砂地燈","glass":3,"copper_ingot":2,"crystal_sand":2},
	RESIDENT_GOALS.GARDEN_CHAIR:{"name":"細框庭園椅","copper_ingot":3,"wood":4},
	INDUSTRY.OBSERVATION_DESK:{"name":"觀察記錄桌","wood":12,"glass":2,"cotton_cloth":2},
	INDUSTRY.LEAF_DESK:{"name":"落葉書桌","wood":14,"hardwood":4},
	INDUSTRY.SEED_CABINET:{"name":"種子標本櫃","wood":14,"glass":6},
	NURSERY_BOX.KIND:{"name":"溫室育苗箱","wood":10,"glass":4},
	INDUSTRY.AQUARIUM:{"name":"小型觀賞魚缸","glass":8,"copper_ingot":2},
	INDUSTRY.COAST_FISH_COUNTER:{"name":"冰藍魚貨台","wood":12,"stone":6},
	INDUSTRY.COAST_AWNING:{"name":"藍條紋遮陽棚","wood":18,"cotton_cloth":8,"fiber":6},
	INDUSTRY.COAST_REGISTER:{"name":"白木收銀櫃","wood":16,"copper_ingot":2},
	INDUSTRY.COAST_CART:{"name":"小栗的招牌攤車","wood":24,"copper_ingot":4,"cotton_cloth":4},
	INDUSTRY.SHELL_TABLE:{"name":"貝殼圓桌","wood":8,"seashell":4},
	INDUSTRY.BEACH_CHAIR:{"name":"折疊沙灘椅","wood":8,"cotton_cloth":4},
	INDUSTRY.GLASS_FLOWER_TABLE:{"name":"玻璃花桌","glass":6,"copper_ingot":4},
	INDUSTRY.VINE_ARCH:{"name":"藤蔓花門","wood":12,"copper_ingot":4,"chime_herb":6},
	INDUSTRY.FOREST_ARCH:{"name":"森林拱門","hardwood":16,"fiber":6,"chime_herb":4},
	INDUSTRY.POT_RACK:{"name":"銅框花架","copper_ingot":6,"wood":8},
	ROOF_FIXTURES.HANGING_POT:{"name":"吊掛花盆","clay":4,"fiber":3},
	"planter":{"name":"窗邊花箱","wood":8,"stone":3},
	"basic_tea_set":{"name":"基本茶具","wood":3,"clay":2},
	"wood_mailbox":{"name":"普通信箱","wood":5,"fiber":1},
	INDUSTRY.MUSHROOM_POST:{"name":"蘑菇門邊郵箱","wood":10,"copper_ingot":2},
	INDUSTRY.QUIET_BIRDHOUSE:{"name":"靜靜小鳥屋","wood":8,"fiber":4},
	"guest_wardrobe":{"name":"旅舍更衣櫃","plank":4,"cotton_cloth":2},
	"inn_lattice_wardrobe":{"name":"木格更衣櫃","hardwood":14,"cotton_cloth":2},
	RESIDENT_GOALS.COAST_WARDROBE:{"name":"藍白更衣棚","wood":12,"cotton_cloth":6},
	RESIDENT_GOALS.FOREST_WARDROBE:{"name":"森林小衣櫃","wood":18,"cotton_cloth":2},
	"inn_fabric_screen":{"name":"織布屏風","hardwood":10,"cotton_cloth":5},
	INDUSTRY.RIVERSIDE_SCREEN:{"name":"河岸屏風","bamboo":10,"cotton_cloth":4},
	INDUSTRY.BAMBOO_LOUNGER:{"name":"竹編躺椅","bamboo":14,"cotton_cloth":3},
	INDUSTRY.TEA_SNACK_SHELF:{"name":"茶屋點心架","bamboo":8,"clay":3},
	INDUSTRY.IMPERFECT_TEA_PAVILION:{"name":"不完美的茶亭","bamboo":30,"wood":10,"cotton_cloth":8},
	"sketch_easel":{"name":"點點的小畫架","wood":4,"fiber":1},
	"rope_rack":{"name":"航海繩掛架","wood":6,"rope":3},
	POSTCARDS.RACK:{"name":"海風明信片架","wood":8,"fiber":2},
	OAR_SIGN.KIND:{"name":"木槳路標","wood":8,"hardwood":2},
	"flower_pot":{"name":"陶花盆","flower_pot":1},
	"sign":{"name":"手刻歡迎牌","wood":5},
	RESIDENT_GOALS.SHELL_CHIME:{"name":"潮紋貝殼風鈴","wood":4,"fiber":2,WANGAN_COAST.SHELL_ITEM:2},
	Squirrel.ORNAMENT:{"name":"橡果掛飾",Squirrel.KIT:1},
	"sofa":{"name":"棉布小沙發","wood":18,"cotton_cloth":2},
	RESIDENT_GOALS.COTTON_SOFA:{"name":"棉布雙人沙發","wood":18,"cotton_cloth":6},
	RESIDENT_GOALS.BAMBOO_BENCH:{"name":"雙人竹長椅","bamboo":10,"fiber":4},
	"sprinkler":{"name":"小型灑水器","copper_ingot":4,"stone":4},
	"large_sprinkler":{"name":"大型灑水器","iron_ingot":10,"glass":4,"woodwork_parts":4},
	"medium_sprinkler":{"name":"中型灑水器","iron_ingot":5,"copper_ingot":2},
	"water_pipe":{"name":"銅水管","pipe_kit":1},
	"water_tank":{"name":"儲水桶","tank_kit":1},
	"mine_drill":{"name":"礦脈採掘機","mine_drill_kit":1},
	"waterworks":{"name":"水力加工台","waterworks_kit":1},
	"water_pump":{"name":"河水泵","pump_kit":1},
	"sawmill":{"name":"鋸木台","sawmill_kit":1},
	"charcoal_kiln":{"name":"炭窯","kiln_kit":1},
	"forester":{"name":"林務工作站","forester_kit":1},
	"conveyor":{"name":"輸送帶","conveyor_kit":1},
	# C13 麵粉磨坊: a 3x3 built straight from materials (no kit). Legacy kit mills use LEGACY_MILL_COST.
	INDUSTRY.MILL:{"name":"麵粉磨坊","wood":25,"stone":15,"woodwork_parts":4},
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
	"festival_memorial_bell":{"name":"風鈴節紀念鐘","wood":6,"copper_joint":2,"glass":1},
	"ceramic_eave_chime":{"name":"簷下陶風鈴","clay":4,"fiber":2},
	"warm_lamp_niche":{"name":"暖燈壁龕","stone":6,"glass":2},
	WALL_FIXTURES.LIFEBUOY:{"name":"救生圈牆飾","fiber":8,"cotton_cloth":3},
	WALL_FIXTURES.BARK_FRAME:{"name":"樹皮畫框","wood":8,"resin":2},
	WALL_FIXTURES.HOME_SIGN:{"name":"手刻門牌","wood":5},
	WALL_FIXTURES.TOOL_BOARD:{"name":"壁掛工具板","wood":8,"copper_ingot":2},
	WALL_FIXTURES.BAMBOO_CURTAIN:{"name":"半透竹簾","bamboo":6,"fiber":2},
	WALL_FIXTURES.WATER_LISTENING_CHIME:{"name":"聽水風鈴","bamboo":4,"copper_ingot":1,"fiber":2},
	"towel_rack":{"name":"浴巾收納架","wood":10,"cotton_cloth":6},
	"inn_welcome_sign":{"name":"暖暖的迎賓牌","hardwood":8,"clay":2},
	"inn_tea_table":{"name":"暖薑茶小桌","hardwood":8,"clay":3},
	"inn_luggage_rack":{"name":"旅人行李架","hardwood":12,"fiber":4},
	"keepsake_lingpopo_memorial":{"name":"鈴婆婆的風鈴節紀念鐘","keepsake_lingpopo_memorial_kit":1},
	"keepsake_xinghe_sign":{"name":"星禾的共同花園牌","keepsake_xinghe_sign_kit":1},
	"keepsake_achao_oar":{"name":"阿潮的紀念木槳","keepsake_achao_oar_kit":1},
	"keepsake_aru_bird":{"name":"阿榆手刻小木鳥","keepsake_aru_bird_kit":1},
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
	"keepsake_nuannuan_room":{"name":"暖暖的房間名牌","keepsake_nuannuan_room_kit":1},
	"keepsake_bobo_cart":{"name":"祖父的礦車","keepsake_bobo_cart_kit":1},
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
	"sugar":{"name":"熬製甜菜糖","ingredients":{"sugar_beet":2},"time":60.0,"yield":2},
	"trout_hotpot":{"name":"雪點鱒魚火鍋","ingredients":{"snow_trout":1,"cabbage":1,"star_mushroom":1},"time":60.0,"yield":4},
	"roasted_sweet_potato":{"name":"烤地瓜","ingredients":{"sweet_potato":2},"time":18.0,"yield":2},
	"seafood_rice":{"name":"海鮮燉飯","ingredients":{"rice":2,"sardine":1,"seaweed":1},"time":40.0,"yield":2},
	"eggplant_rice":{"name":"茄子燴飯","ingredients":{"rice":2,"eggplant":1},"time":30.0,"yield":2},
	"mist_tea_brew":{"name":"霧竹茶飲","ingredients":{"mist_tea":2},"time":20.0,"yield":2},
	"ginger_tea":{"name":"暖薑茶","ingredients":{"ginger":1,"sugar":1},"time":60.0,"yield":2},
	"watermelon_platter":{"name":"夏日西瓜盤","ingredients":{"watermelon":1},"time":8.0,"yield":4},
	# corn_chowder 玉米濃湯（規劃書第 14 章「玉米、牛奶・團隊分享餐」；數量、30 秒、四份與
	# 售價 30 是設計值，規劃書沒有給）。共餐桌的第三道分享餐（community.gd DISHES）。
	"corn_chowder":{"name":"玉米濃湯","ingredients":{"sweet_corn":2,"milk":1},"time":30.0,"yield":4},
	"tea_pudding":{"name":"茶香布丁","ingredients":{"tea_leaf":1,"milk":1,"egg":1},"time":120.0,"yield":3},
	"star_rice_ball":{"name":"星點飯糰","ingredients":{"rice":2,"seaweed":1},"time":60.0,"yield":3},
	"strawberry_toast":{"name":"草莓吐司","ingredients":{"bread":1,"strawberry_jam":1},"time":20.0,"yield":2},
	# C12 D05 / D14: dishes that had no recipe at all. Cookable only on the 2x2 公共廚房灶台
	# (stove_recipes); the numbers are KitchenStove.DISHES, the single source of the D-table.
	"forest_mushroom_soup":{"name":"森林菇湯","ingredients":{"star_mushroom":2,"chime_herb":1},"time":60.0,"yield":2},
	"rainbow_skewer":{"name":"彩虹蔬菜串","ingredients":{"radish":1,"carrot":1,"eggplant":1},"time":60.0,"yield":3}}
const OTHER_SALES := {"duck_egg":34,"quality_duck_egg":42,"quality_egg":37,"quality_milk":45,"quality_wool":60,WANGAN_COAST.SHELL_ITEM:18,"fired_brick":16,"ochre_earth":10,"iron_ingot":20,"seafood_rice":62,"milk":36,"wool":48,"tea_pudding":60,"corn_chowder":30,"egg":30,"soup":32,"bread":48,"salad":36,"baked_potato":36,"grilled_fish":26,"carrot_soup":50,"pumpkin_pie":80,"garden_cookie":36,"salt_grilled_fish":34,"strawberry_jam":49,"cucumber_salad":26,"trout_hotpot":60,"roasted_sweet_potato":41,"eggplant_rice":51,"mist_tea_brew":44,"watermelon_platter":38}
## Flower seeds, blue_dye and sugar are deliberately absent from CROPS prices and
## OTHER_SALES: they can never be sold or shipped (no seed-saving arbitrage).
## sea_salt is likewise never sellable, shippable or buyable (no automation pump).
const NAMES := {"copper_pick":CRAFT.copper_pick.name,"iron_pick":CRAFT.iron_pick.name,"precision_pick":CRAFT.precision_pick.name,"copper_axe":CRAFT.copper_axe.name,"iron_axe":CRAFT.iron_axe.name,"precision_axe":CRAFT.precision_axe.name,"copper_hoe":CRAFT.copper_hoe.name,"iron_hoe":CRAFT.iron_hoe.name,"precision_hoe":CRAFT.precision_hoe.name,"copper_can":CRAFT.copper_can.name,"iron_can":CRAFT.iron_can.name,"precision_can":CRAFT.precision_can.name,"copper_rod":CRAFT.copper_rod.name,"iron_rod":CRAFT.iron_rod.name,"precision_rod":CRAFT.precision_rod.name,"copper_seed_pouch":CRAFT.copper_seed_pouch.name,"iron_seed_pouch":CRAFT.iron_seed_pouch.name,"precision_seed_pouch":CRAFT.precision_seed_pouch.name,"copper_sickle":CRAFT.copper_sickle.name,"iron_sickle":CRAFT.iron_sickle.name,"precision_sickle":CRAFT.precision_sickle.name,XIAOLI_SHOP.SCALE_ITEM:XIAOLI_SHOP.SCALE_NAME,REGIONS.Bamboo.ITEM:"竹材",INDUSTRY.TEA_SET:CRAFT[INDUSTRY.TEA_SET].name,INDUSTRY.TABLE_VASE:CRAFT[INDUSTRY.TABLE_VASE].name,"table_vase_bluebell":"桌邊花瓶・鈴蘭藍花","table_vase_orange":"桌邊花瓶・蜜橙花","shell_bottle_scallop":CRAFT.shell_bottle_scallop.name,"shell_bottle_conch":CRAFT.shell_bottle_conch.name,"shell_bottle_tide":CRAFT.shell_bottle_tide.name,"duck_egg":"鴨蛋", "quality_duck_egg":"優良鴨蛋",Squirrel.ACORN:"橡果", Squirrel.KIT:"橡果掛飾","quality_egg":"優良雞蛋","quality_milk":"優良鮮奶","quality_wool":"優良羊毛","quality_radish":"優良奶白蘿蔔", "quality_lettuce":"優良圓葉萵苣", "quality_wheat":"優良星點小麥", "quality_carrot":"優良糖心胡蘿蔔", "quality_potato":"優良小馬鈴薯", "quality_tomato":"優良太陽番茄", "quality_pumpkin":"優良琥珀南瓜", "quality_cauliflower":"優良雲朵花椰菜", "quality_sweet_corn":"優良甜玉米", "quality_strawberry":"優良蜜香草莓", "quality_cucumber":"優良波點黃瓜", "quality_cabbage":"優良雪白高麗菜", "quality_sugar_beet":"優良霜糖甜菜", "quality_star_mushroom":"優良星夜菇", "quality_sweet_potato":"優良栗香地瓜", "quality_eggplant":"優良紫絨茄子", "quality_rice":"優良月牙稻米", "quality_watermelon":"優良小圓西瓜", "quality_ginger":"優良暖泉薑", "quality_cotton":"優良棉球花", "quality_mist_tea":"優良霧竹茶", "quality_bluebell":"優良鈴蘭藍花", "quality_orange_blossom":"優良蜜橙花", "quality_chime_herb":"優良風鈴香草", WANGAN_COAST.SHELL_ITEM:"潮紋貝殼","ginger_tea":"暖薑茶","forest_mushroom_soup":"森林菇湯","rainbow_skewer":"彩虹蔬菜串","animal_collector_kit":"動物自動收集器組件","field_sprinkler_kit":"小型灑水器組件","medium_sprinkler_kit":"中型灑水器組件","large_sprinkler_kit":"大型灑水器組件","orange_dye":"橙色染料","fired_brick":"紅磚",TERRACOTTA_ROOF.TILE:TERRACOTTA_ROOF.TILE_NAME,"woodwork_parts":"木工零件","iron_ore":"鐵礦","iron_ingot":"鐵錠","copper_ingot":"銅錠","hardwood":"硬木","keepsake_lingpopo_memorial_kit":"鈴婆婆的風鈴節紀念鐘","keepsake_xinghe_sign_kit":"星禾的共同花園牌","keepsake_achao_oar_kit":"阿潮的紀念木槳","seafood_rice":"海鮮燉飯","keepsake_aru_bird_kit":"阿榆手刻小木鳥","egg_basket":"收集籃","flower_pot":"陶花盆","rope":"繩索","strawberry_toast":"草莓吐司","seaweed":"海苔","star_rice_ball":"星點飯糰","tea_pudding":"茶香布丁","corn_chowder":"玉米濃湯","supply_box_kit":"便攜補給箱","moon_squid":"月光小魷","gold_shrimp":"金邊蝦","sardine":"藍背沙丁","flounder":"奶油比目魚","crystal_sand":"晶砂","ochre_earth":"赭土","vein_quartz":"脈石英","warm_stone":"暖岩片","glass":"溫室玻璃","tea_leaf":"新鮮茶葉","clay":"陶土","tea_jar":"陶罐","tea_returned_jar":"回收陶罐","tea_worn_jar":"磨損陶罐","tea_spent_jar":"待修陶罐","tea_light":"淺焙茶","tea_deep":"深焙茶","mine_drill_kit":"礦脈採掘機","waterworks_kit":"水力加工台","gold_ore":"含金礦料","gold_sample":"金工收藏樣本","wood":"木材", "stone":"石材", "fiber":"纖維", "radish":"蘿蔔", "lettuce":"萵苣", "wheat":"小麥", "radish_seed":"蘿蔔種子", "lettuce_seed":"萵苣種子", "wheat_seed":"小麥種子", "carp":"圓肚鯽魚", "minnow":"銀線溪魚", "redfish":"紅尾小鯉", "loach":"斑點泥鰍", "egg":"雞蛋", "feed":"飼料", "soup":"蘿蔔湯", "bread":"麵包", "sapling":"小樹苗","carrot":"胡蘿蔔","potato":"馬鈴薯","tomato":"番茄","carrot_seed":"胡蘿蔔種子","potato_seed":"馬鈴薯種子","tomato_seed":"番茄種子","salad":"菜園沙拉","baked_potato":"烤馬鈴薯","grilled_fish":"香煎鯽魚","carrot_soup":"胡蘿蔔濃湯","reinforced_pick":"強化石鎬","copper_ore":"銅礦","copper_joint":"銅接頭","sprinkler_kit":"小型灑水器","plank":"木板","resin":"樹脂","charcoal":"木炭","pipe_kit":"銅水管","tank_kit":"儲水桶","pump_kit":"河水泵","sawmill_kit":"鋸木台","kiln_kit":"炭窯","forester_kit":"林務工作站","conveyor_kit":"輸送帶","tiller":"手推耕田機","seeder":"手推播種機","harvester":"手推收割機","pumpkin":"南瓜","pumpkin_seed":"南瓜種子","flour":"麵粉","pumpkin_pie":"南瓜派","mill_kit":"麵粉磨坊","bluebell":"鈴蘭藍花","orange_blossom":"蜜橙花","chime_herb":"風鈴香草","bluebell_seed":"鈴蘭藍花種子","orange_blossom_seed":"蜜橙花種子","chime_herb_seed":"風鈴香草種子","blue_dye":"藍色染料","sugar":"糖","garden_cookie":"花園餅乾","sea_salt":"海鹽","salt_wheel_kit":"鹽田水車組","salt_rake_kit":"收鹽台組","salt_grilled_fish":"香煎溪魚","cauliflower":"花椰菜","cauliflower_seed":"花椰菜種子","sweet_corn":"甜玉米","sweet_corn_seed":"甜玉米種子","star_spot":"星斑魚","bamboo_ayu":"竹影香魚","glass_shrimp":"玻璃小蝦","snow_trout":"雪點鱒魚","strawberry":"草莓","strawberry_seed":"草莓種子","cucumber":"黃瓜","cucumber_seed":"黃瓜種子","strawberry_jam":"草莓果醬","cucumber_salad":"涼拌黃瓜","cabbage":"高麗菜","cabbage_seed":"高麗菜種子","sugar_beet":"甜菜","sugar_beet_seed":"甜菜種子","star_mushroom":"星夜菇","star_mushroom_seed":"星夜菇菌種","trout_hotpot":"雪點鱒魚火鍋","sweet_potato":"地瓜","sweet_potato_seed":"地瓜種子","eggplant":"茄子","eggplant_seed":"茄子種子","rice":"稻米","rice_seed":"稻種","roasted_sweet_potato":"烤地瓜","eggplant_rice":"茄子燴飯","watermelon":"西瓜","watermelon_seed":"西瓜種子","ginger":"暖泉薑","ginger_seed":"薑種","cotton":"棉球花","cotton_seed":"棉球花種子","mist_tea":"霧竹茶","mist_tea_seed":"霧竹茶種","mist_tea_brew":"霧竹茶飲","watermelon_platter":"夏日西瓜盤","milk":"鮮奶","wool":"羊毛","cotton_cloth":"布料","wool_cloth":"羊毛布","veg_basket_rack_kit":"菜籃小架","relay_crate_stack_kit":"接力菜箱堆","carp_banner_kit":"鯽魚布旗","float_garland_kit":"浮球串飾","lantern_post_kit":"紙燈籠柱","flower_arch_kit":"花草拱架","trio_keepsake_kit":"三活動紀念牌","water_share_plaque_kit":"分水木牌","diversion_gate_kit":"分流閘","water_tower_kit":"水塔","mine_lantern_kit":"礦燈","tea_ware_kit":"茶陶組","salt_basket_kit":"鹽籃","keepsake_aru_kit":"有點歪的第一塊板","keepsake_milu_kit":"試吃會的空碗","keepsake_bobo_kit":"排成小島的石頭","keepsake_chacha_kit":"換下來的舊竹片","keepsake_achao_kit":"鬆開的舊繩結","keepsake_mianmian_kit":"縫線有點歪的玩具","keepsake_xinghe_kit":"留了一格空白的花圃圖紙","keepsake_lingpopo_kit":"留著你的顏色的鈴","keepsake_xiaoli_kit":"招牌的試寫木片","keepsake_luoluo_kit":"寫給以後的信封","keepsake_diandian_kit":"畫著放鬆的手的速寫","keepsake_nuannuan_kit":"亮起來的門牌","keepsake_nuannuan_room_kit":"暖暖的房間名牌","keepsake_bobo_cart_kit":"祖父的礦車"}
## T071 紀念票兌換品（*_kit，= SOUVENIR.items()）刻意不在 CROPS／FISH／OTHER_SALES：
## 不能出貨、不能在攤位出售或上市集；trade_items() 也排除，不能和其他玩家交易。
var state: Dictionary
const PUBLIC_BUILD_PLOT := Rect2i(40,24,4,2)
const PUBLIC_BUILD_DENIED := "渡口北側公共地塊需要島主或管理員授權施工。"
var public_build_access: Callable

func allows_public_build(token:String,p:Vector2i) -> bool:
	return _region!=REGIONS.HOME or not PUBLIC_BUILD_PLOT.has_point(p) or not public_build_access.is_valid() or public_build_access.call(token)
var save_path := ""
var save_error := ""
var last_saved_at := 0
var recovered_from_backup := false
var rejected_path := ""
## Why the last step() returned false: "" (ok/paused), STEP_FAIL_SALT or
## STEP_FAIL_SAVE. Either failure rolled the whole tick back (no save).
var step_error := ""
const STEP_FAIL_SALT := "salt_step_rejected"
const STEP_FAIL_SAVE := "save_failed"
var active_tokens:Dictionary={}
## T066 N01-3 transient co-sitting beside 阿榆 (see aru_bench_rest.gd). Instance-only: never in state/save.
var aru_bench:Dictionary={}
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
	state = {"version":SAVE_SCHEMA.VERSION,"regions":{}, "time":0.0, "players":{}, "crops":{}, "objects":{}, "ground":{}, "roofs":{}, "edges":{}, "removed":{}, "damage":{}, "board":false, "donations":{"wood":0,"stone":0}, "events":[], "committed":0, "construction":CONSTRUCTION_HISTORY.fresh()}
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
	if not state.has("seaweed_ready"):state.seaweed_ready=0.0
	if not state.has("wangan_shell_ready"):state.wangan_shell_ready=0.0
	if not state.has("wangan_star_walk"):state.wangan_star_walk=false
	if not state.has("wangan_star_sand_ready"):state.wangan_star_sand_ready=0.0
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
	return WANGAN_COAST.shore_cell(p) or WANGAN_COAST.star_shore(p) or original_home_land(p)

static func original_home_land(p:Vector2i)->bool:
	var d := Vector2((p.x-39.5)/36.0, (p.y-29.5)/26.0)
	return p.x >= 0 and p.y >= 0 and p.x < SIZE.x and p.y < SIZE.y and d.length_squared() < 1.0 + sin(p.y*0.7)*0.035

static func base_resource(p: Vector2i, region: String = REGIONS.HOME) -> String:
	if region != REGIONS.HOME:return REGIONS.resource(p,region)
	if (WANGAN_COAST.shore_cell(p) or WANGAN_COAST.star_shore(p)) and not original_home_land(p):return ""
	if WANGAN_MEMORY.COURT.has_point(p):return ""
	# Keep the illustrated village paths walkable and visually clear. Existing
	# player-planted trees remain in the saved forest layer and are unaffected.
	if VILLAGE_LAYOUT.path_at(Vector2(p)+Vector2(0.5,0.5)):return ""
	if (p.x>=46 and p.x<=51 and p.y>=22 and p.y<=29) or p in [Vector2i(38,29),Vector2i(54,25),COPPER_CELL]:return ""
	if not land(p) or (p.x >= 35 and p.x <= 45 and p.y >= 27 and p.y <= 37): return ""
	if p.x == 55 or p.x == 56 or p==SEAWEED_CELL: return ""
	var h: int = absi(p.x*7127 + p.y*19391 + p.x*p.y*193)
	if h % 17 == 0: return "tree"
	if h % 23 == 0: return "rock"
	if h % 31 == 0: return "grass"
	return ""

func resource(p: Vector2i) -> String:
	var planted:Dictionary=state.forest.get(key(p),{})
	if not planted.is_empty():return "tree" if planted.mature else "sapling"
	if _region==REGIONS.HOME and WOODLAND.stumps(state).has(key(p)):return "stump"
	return "" if state.removed.has(key(p)) else base_resource(p,_region)

func can_restore_woodland_tree(tile:String)->bool:
	var p:=cell(tile)
	if not WOODLAND.GROVE.has_point(p) or water(p) or protected(p) or base_resource(p)!="tree":return false
	for layer:String in ["objects","ground","roofs","crops","forest"]:
		if state[layer].has(tile):return false
	if state.get("gather_drops",{}).get(REGIONS.HOME,{}).has(tile):return false
	if INDUSTRY.is_mill_front(state.objects,p):return false
	for token:String in regional_tokens():
		var person:Dictionary=state.players[token]
		if INDUSTRY.foot_box_hits(Vector2(person.x,person.y),[p]):return false
	return true

func is_land(p: Vector2i) -> bool:
	return land(p,_region)

func tree_planting_problem(token:String,p:Vector2i)->String:
	if water(p) or protected(p):return "這裡是水域或公共通道，請換個位置"
	# C13: a sapling grows into a blocking tree, so it may not take the open cell in front of a mill entrance.
	if INDUSTRY.is_mill_front(state.objects,p):return INDUSTRY.MILL_FRONT_BLOCKED
	var tile:=key(p)
	if resource(p)!="" or state.crops.has(tile) or state.objects.has(tile) or state.ground.has(tile) or state.roofs.has(tile):
		return "樹苗需要一格空地，不能種在農田或建物上"
	if int(state.players.get(token,{}).get("inventory",{}).get("sapling",0))<1:
		return "沒有樹苗了，砍樹會得到樹苗，也可以向小栗購買"
	return ""

func water(p: Vector2i) -> bool:
	if _region != REGIONS.HOME:return REGIONS.water(p,_region)
	return home_water(p,STONE_WORKSHOP.bridge_open(state))

static func home_water(p:Vector2i,bridge_open:bool) -> bool:
	if WANGAN_COAST.STAR_POOL.has_point(p):return true
	if not land(p): return true
	return (p.x == 55 or p.x == 56) and not (bridge_open and p.y >= 29 and p.y <= 31)

func bobo_sites() -> Dictionary:
	return BOBO_WORKSHOP.sites(state)

func protected(p: Vector2i) -> bool:
	if _region==MINES.MUD_REGION and p.y<MINES.MUD_ALCOVE_EDGE and is_land(p):return true
	# 石殼蟹: its three B5 cells take no new builds. A cell an older save already uses stays the
	# owner's to use and clear; it becomes reserved once empty.
	if _region==CRAB.REGION and p in CRAB.footprint() and crab_site_open() and not CRAB.cell_occupied(state,p):return true
	if _region==PORTER.REGION and p in PORTER.ROUTE_CELLS and porter_site_open():return true
	if _region==MEADOW.REGION and p in MEADOW.FOOTPRINT and state.get("picnic",false) and MEADOW.cell_open(state,p):return true
	if _region == REGIONS.JINGUASHI and p in bobo_sites().values():return true
	if _region==REGIONS.JINGUASHI and p==PARTY_CART.SURFACE_PORTAL and not state.objects.has(key(p)):return true
	if _region==REGIONS.LANYANG and p in RESIDENT_GOALS.GARDEN_POTS:return true
	if _region != REGIONS.HOME:return REGIONS.transit_walkway(p,_region) or REGIONS.protected(p,_region)
	if WANGAN_COAST.shore_cell(p) and not original_home_land(p):return true
	if WANGAN_COAST.star_shore(p) or p==WANGAN_COAST.STAR_REPAIR:return true
	if p==WANGAN_COAST.DOCK_ORDERS and state.get("wangan_star_walk",false):return true
	if p==WANGAN_COAST.SALT_PARCEL and state.get("wangan_star_walk",false):return true
	if WANGAN_MEMORY.COURT.has_point(p) and WANGAN_MEMORY.courtyard_available(state):return true
	if MILL_RESTORATION.reserved(p) and MILL_RESTORATION.site_clear(state):return true
	# T042: donated public-kitchen stove/seats are permanently public (HOME only).
	if PUBLIC_KITCHEN.is_site_cell(state,p):return true
	if p in RESIDENT_GOALS.ARU_PARK_SLOTS.values():return true
	if p in [REGIONS.exit_cell(REGIONS.HOME),Vector2i(REGIONS.spawn(REGIONS.HOME)),Vector2i(WANGAN_COAST.FERRY_LANDING)]:
		var tile := key(p)
		for layer in ["objects","ground","roofs","crops","forest"]:
			if state[layer].has(tile):return false
		return true
	if WANGAN_COAST.FERRY_ACCESS.has_point(p):return true
	if p in [Vector2i(38,29),Vector2i(44,31),Vector2i(54,25)]:return true
	if p in MARKET.CANDIDATES and p==MARKET.active_cell(state):return true # T071 市集攤位（解鎖後保留）
	if HARVEST.reserved(state,p):return true # T071 豐收接力場地（解鎖後空著的格子保留）
	if FISH_MEET.reserved(state,p):return true # T071 河岸釣魚會告示牌（解鎖後空著時保留）
	if SHOWCASE.reserved(state,p):return true # T071 家園布置題告示牌與展示地塊（解鎖後空著的格子保留）
	if state.get("picnic",false) and p in [LOST_CHICKS.SIGN,LOST_CHICKS.PEN]:return true
	if SOUVENIR.reserved(state,p):return true # T071 紀念品交換攤（解鎖後使用中的那一格保留）
	if PUBLIC_TILLER.reserved(state,p):return true # T064 公用耕田機的農機架（野餐後使用中的那一格保留）
	if MEMORY_EXHIBIT.reserved(state,p):return true # 第 40 章地方記憶展展台（風鈴節開幕後使用中的那一格）
	return (p.x >= 38 and p.x <= 44 and p.y >= 28 and p.y <= 31) or (p.x >= 54 and p.x <= 57) or (p.x==39 and p.y in [32,33]) or p==Vector2i(45,34)

func blocked(p: Vector2i) -> bool:
	if _region==REGIONS.Bamboo.REGION and p in REGIONS.Bamboo.CLUMPS:return true
	if _region==WARM_SPRINGS.REGION and (WARM_SPRINGS.BATH_FOOTPRINT.has_point(p) or WARM_SPRINGS.INN_FOOTPRINT.has_point(p)):return true
	if _region==WARM_SPRINGS.REGION and WARM_SPRINGS.room_blocked(p):return true
	if _region in TRANSIT.TEA_STOPS and REGIONS.tea_blocked(p,_region):return true
	if _region==TEA_HOUSE_INTERIOR.REGION and TEA_HOUSE_INTERIOR.blocked(p):return true
	if _region==POTTERY_WORKSHOP_INTERIOR.REGION and POTTERY_WORKSHOP_INTERIOR.blocked(p):return true
	if _region==TEA_CERAMICS.MAOKONG and p==TEA_REVISIT.HOUSE_SITE and TEA_REVISIT.house_open(state):return true
	if _region in TRANSIT.LOCAL and (not is_land(p) or TRANSIT.blocked(p,_region)):return true
	if _region == FLOWER_NURSERY.REGION and (not is_land(p) or FLOWER_NURSERY.blocked(p)):return true
	if _region == SALT_PAN.REGION and (not is_land(p) or SALT_PAN.blocked(p)):return true
	if water(p): return true
	if _region in MINES.IDS and p in MINES.NODES:return true
	# 石殼蟹: only the little side cart is solid (same cell for everyone). The crab's own cell
	# differs per player, so it is drawn but never blocks.
	if p==CRAB.CART and _region==CRAB.REGION and crab_available():return true
	if p==PORTER.CRATE and _region==PORTER.REGION and porter_site_open() and PORTER.site_clear(state):return true
	if _region==MEADOW.REGION and p in MEADOW.FOOTPRINT and state.get("picnic",false) and MEADOW.site_clear(state):return true
	if _region == REGIONS.JINGUASHI and (p in JINGUASHI.NODES or JINGUASHI.ENTRANCE_FOOTPRINT.has_point(p)):return true
	if _region == REGIONS.JINGUASHI and p == bobo_sites().table:return true
	if _region == REGIONS.HOME:
		if MILL_RESTORATION.SITE.has_point(p) and p!=MILL_RESTORATION.DOOR and MILL_RESTORATION.site_clear(state):return true
		if WANGAN_COAST.star_shore(p) and not state.get("wangan_star_walk",false):return true
		if WANGAN_MEMORY.HOUSE_WALL.has_point(p) and WANGAN_MEMORY.courtyard_available(state):return true
		if state.get("festival_story_open",false) and p in Village.FESTIVAL_SPOTS.values():return true
		if (p in COMMUNITY.CANDIDATES and p == COMMUNITY.table_cell(state)) or p==COPPER_CELL or (p in SHIPPING.CANDIDATES and p == SHIPPING.cell_for(state)):return true
		if p in MARKET.CANDIDATES and p == MARKET.active_cell(state):return true
		if HARVEST.reserved(state,p):return true
		if FISH_MEET.reserved(state,p):return true
		if SHOWCASE.blocks(state,p):return true # 只有告示牌擋路，展示地塊照樣能走
		if SOUVENIR.blocks(state,p):return true # T071 紀念品交換攤擋路
		if PUBLIC_TILLER.reserved(state,p):return true # T064 農機架擋路
		if MEMORY_EXHIBIT.blocks(state,p):return true # 第 40 章地方記憶展展台擋路
		if p == Vector2i(40,29) or p == Vector2i(43,29): return true
		if p in [Vector2i(38,29),Vector2i(44,31),Vector2i(54,25)]:return true
	var r := resource(p)
	if r == "tree" or r == "rock": return true
	var o: Dictionary = state.objects.get(key(p), {})
	if o.get("type","")=="door":return not o.get("open",false)
	return o.get("type", "") in UNDO_SOLID and not INDUSTRY.is_folded_passage(o)

func add_player(token: String, name: String, landing:=SPAWN) -> void:
	active_tokens[token]=true
	var new_player:bool=not state.players.has(token)
	if new_player:
		state.players[token] = {"name":name.left(12), "region":REGIONS.HOME, "travel_epoch":0, "travel_book":TRANSIT.fresh(), "mine_energy":100, "x":landing.x, "y":landing.y, "coins":120, "inventory":{"wood":12,"stone":4,"fiber":10,"radish_seed":5,"lettuce_seed":3,"wheat_seed":3,"sapling":2}, "receipts":{}, "harvests":0, "builds":0}
		if landing==WANGAN_COAST.FERRY_LANDING:state.players[token][CHAPTER_ONE.PERSONAL_START]=true
	else: state.players[token].name = name.left(12)
	Village.ensure_player(state.players[token])
	Collections.ensure_player(state.players[token])
	if not state.players[token].has("crafted_reinforced_pick"):state.players[token].crafted_reinforced_pick=false
	var current := player_region(token)
	switch_region(current)
	var person: Dictionary = state.players[token]
	person.erase(RESIDENT_GOALS.MASTER_BENCH_SEAT)
	person.erase(REGIONS.Springs.REST_SEAT_KEY)
	person.erase(TEA_HOUSE_INTERIOR.SEAT_KEY)
	person.erase(RESIDENT_GOALS.DIANDIAN_SEAT_KEY)
	aru_bench_release(token)
	if not can_stand(Vector2(person.x,person.y)) or (new_player and not can_enter_room_floor(token,Vector2(person.x,person.y))):
		var fallback:Vector2=landing if new_player else SPAWN
		var point := safe_arrival(REGIONS.spawn(current) if current != REGIONS.HOME else fallback,token)
		if point==Vector2.ZERO and current==REGIONS.HOME and fallback!=SPAWN:point=safe_arrival(SPAWN,token)
		if point != Vector2.ZERO:
			person.x = point.x
			person.y = point.y
	switch_region(REGIONS.HOME)

func safe_arrival(preferred: Vector2,token:="") -> Vector2:
	if can_stand(preferred) and can_enter_room_floor(token,preferred):return preferred
	for radius in range(1,5):
		for y in range(-radius,radius+1):
			for x in range(-radius,radius+1):
				var candidate := preferred + Vector2(x,y)
				if can_stand(candidate) and can_enter_room_floor(token,candidate):return candidate
	return Vector2.ZERO

## Older worlds can have walls around an arrival cell. Keep those buildings and
## land on the nearest tile that still connects to the public route destination.
func safe_transit_arrival(preferred:Vector2,token:String)->Vector2:
	var arrival:=safe_arrival(preferred,token)
	if not REGIONS.TRANSIT_WALKWAYS.has(_region):return arrival
	var route:Dictionary=REGIONS.TRANSIT_WALKWAYS[_region]
	var arrival_cell:=Vector2i(arrival.floor())
	if arrival_cell==Vector2i(REGIONS.spawn(_region)) and _walkway_open(token,arrival_cell,route.strips):return arrival
	var destination:=safe_arrival(Vector2(route.destination)+Vector2(0.5,0.5),token)
	if destination==Vector2.ZERO:return arrival
	var start:=Vector2i(destination.floor())
	var bounds:=Rect2i(Vector2i.ZERO,SIZE)
	var queue:Array[Vector2i]=[start]
	var visited:Dictionary={start:true}
	var closest:=destination
	var best_distance:=preferred.distance_squared_to(closest)
	var index:=0
	while index<queue.size():
		var cell:=queue[index]
		index+=1
		if arrival!=Vector2.ZERO and cell==arrival_cell:return arrival
		var center:=Vector2(cell)+Vector2(0.5,0.5)
		var distance:=preferred.distance_squared_to(center)
		if distance<best_distance:
			closest=center
			best_distance=distance
		for offset:Vector2i in [Vector2i.DOWN,Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT]:
			var neighbor:=cell+offset
			if not bounds.has_point(neighbor) or visited.has(neighbor):continue
			var neighbor_center:=Vector2(neighbor)+Vector2(0.5,0.5)
			if not can_stand(neighbor_center) or not can_enter_room_floor(token,neighbor_center):continue
			if not _activity_can_step(token,neighbor,cell):continue
			visited[neighbor]=true
			queue.append(neighbor)
	return closest

func _walkway_open(token:String,previous:Vector2i,strips:Array)->bool:
	for strip:Rect2i in strips:
		for y in range(strip.position.y,strip.end.y):
			for x in range(strip.position.x,strip.end.x):
				var cell:=Vector2i(x,y)
				if cell==previous:continue
				if not _activity_can_step(token,previous,cell):return false
				previous=cell
	return true

func player_region(token: String) -> String:
	return state.players.get(token, {}).get("region", REGIONS.HOME)

func own_crop_summary(token:String) -> Dictionary:
	return crop_summaries([token])[token]

func crop_summaries(tokens:Array) -> Dictionary:
	var summaries:={}
	for token:String in tokens:summaries[token]={"ready":0,"growing":0,"dry":0}
	for region:String in REGIONS.ALL:
		var layers:Dictionary=_layers_of(region)
		for plot:Dictionary in layers.get("crops",{}).values():
			var summary:Variant=summaries.get(plot.get("owner"))
			if summary==null:continue
			var kind:=str(plot.get("kind",""))
			if not CROPS.has(kind):continue
			if float(plot.get("growth",0))>=float(CROPS[kind].time):summary.ready+=1
			else:
				summary.growing+=1
				if not plot.get("wet",false):summary.dry+=1
	return summaries

func island_project_mask() -> int:
	return (int(STONE_WORKSHOP.bridge_open(state))
		| (int(state.get("lanyang_life",{}).get("repaired",false))<<1)
		| (int(state.get("flower_nursery",{}).get("garden",{}).get("complete",false))<<2)
		| (int(SALT_PAN.repaired(state))<<3)
		| (int(state.get("public_kitchen",{}).get("opened",false))<<4)
		| (int(int(state.get("mine_depths",{}).get("unlocked",1))>=5)<<5))

## D16: has the festival preparation that unlocks 糰糰火鍋 on the C12 stove been done? (host / state)
func festival_prep_unlocked() -> bool:
	return KITCHEN_STOVE.festival_prep_done(state,island_project_mask(),ISLAND_NOTES.project_mask())

## Same rule for a client snapshot (display only; the host decides through festival_prep_unlocked()).
static func festival_prep_unlocked_in(snapshot:Dictionary) -> bool:
	var story:Dictionary=snapshot.get("festival_story",{}) if snapshot.get("festival_story",{}) is Dictionary else {}
	var opened: Variant = story.get("opened",false)
	return KITCHEN_STOVE.festival_prep_done(snapshot,int(story.get("projects",0)),ISLAND_NOTES.project_mask()) or (opened is bool and opened)

## C12 stove lock (D16 festival + D11/D15 resident events), host side: is `dish` locked for `person`
## on a stove of type `stove_kind`? Reads the player's own completed events (RESIDENT_GOALS.done).
func stove_dish_locked(person:Dictionary,stove_kind:String,dish:String) -> bool:
	var gate:Dictionary=KITCHEN_STOVE.gate(stove_kind,dish)
	if gate.is_empty():return false
	var event_done: bool = gate.kind=="event" and RESIDENT_GOALS.done(person,str(gate.resident)).has(int(gate.stage))
	if gate.kind=="market":event_done=SUMMER_MARKET.recipe_known(person)
	if gate.kind=="forest":event_done=FOREST_MUSHROOM.done(person)
	return KITCHEN_STOVE.locked(stove_kind,dish,festival_prep_unlocked(),event_done)

## Same rule for the viewer's own snapshot (display only). `resident_goals` is the own-only summary Session
## attaches (RESIDENT_GOALS.view): a stage is done exactly when done(person,resident).has(stage).
static func stove_dish_locked_in(snapshot:Dictionary,stove_kind:String,dish:String) -> bool:
	var gate:Dictionary=KITCHEN_STOVE.gate(stove_kind,dish)
	if gate.is_empty():return false
	var event_done:=false
	if gate.kind=="event":
		var goals:Variant=snapshot.get("resident_goals",{})
		var own:Variant=goals.get(gate.resident,{}) if goals is Dictionary else {}
		var entry:Variant=own.get(str(int(gate.stage)),{}) if own is Dictionary else {}
		event_done=entry is Dictionary and entry.get("state","")=="done"
	elif gate.kind=="market":
		event_done=SUMMER_MARKET.recipe_known_in(snapshot)
	elif gate.kind=="forest":
		var own: Variant=snapshot.get("own_forest_mushroom")
		event_done=own is Dictionary and own.get("done") is bool and own.done
	return KITCHEN_STOVE.locked(stove_kind,dish,festival_prep_unlocked_in(snapshot),event_done)

static func forest_mushroom_tree(snapshot: Dictionary, at: Vector2) -> Vector2i:
	var summary: Dictionary=snapshot.get("own_forest_mushroom",{})
	if snapshot.get("region_id",REGIONS.HOME)!=REGIONS.HOME or summary.get("next")!=FOREST_MUSHROOM.SURVEY:return FOREST_MUSHROOM.NO_TREE
	var nearest:=FOREST_MUSHROOM.NO_TREE
	var limit:=FOREST_MUSHROOM.REACH
	var origin:=Vector2i(floori(at.x),floori(at.y))
	var removed: Dictionary=snapshot.get("removed",{})
	var planted: Dictionary=snapshot.get("forest",{})
	for y in range(-3,4):
		for x in range(-3,4):
			var tile:=origin+Vector2i(x,y)
			var distance:=at.distance_to(Vector2(tile)+Vector2(0.5,0.5))
			if distance>limit or not land(tile) or not FOREST_MUSHROOM.forest_cell(tile):continue
			var cell_key:=key(tile)
			if removed.has(cell_key) or planted.has(cell_key) or base_resource(tile,REGIONS.HOME)!="tree":continue
			nearest=tile
			limit=distance
	return nearest

func island_news_project_mask() -> int:
	var mine:Dictionary=state.get("mine_depths",{})
	var local:=int(MINES.hoist_ready(mine)) \
		| (int(int(mine.get("unlocked",1))>=MINES.MAX_DEPTH)<<1) \
		| (int(state.get(WARM_SPRINGS.BATH_KEY,false))<<2) \
		| (int(TEA_REVISIT.house_open(state))<<3)
	return island_project_mask() | (local<<ISLAND_NOTES.PROJECTS.size())

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

const GATHER_DROP_DELAY := 0.60
const GATHER_RESERVATION_SECONDS := 30.0
const GATHER_PICKUP_RADIUS := 1.05
# Filled by the current step; Session consumes these only after it commits.
var gather_pickup_events: Array[Dictionary] = []
const GATHER_ASSIST_WINDOW:=15.0
const GATHER_ASSIST_REACH:=3.2
# Swing history is live session state. Earned participation and XP are saved.
var _gather_work:Dictionary={}

func gather_assist_candidates(actor:String,tile:Vector2i)->Array[String]:
	var region:=player_region(actor)
	var marks:Dictionary=_gather_work.get(region+"/"+key(tile),{})
	var now:=float(state.time)
	var target:=Vector2(tile)+Vector2(0.5,0.5)
	var result:Array[String]=[]
	for member:String in marks:
		if member==actor or not active_tokens.has(member) or player_region(member)!=region:continue
		var person:Dictionary=state.players.get(member,{})
		if person.is_empty() or now>=float(marks[member]):continue
		if Vector2(person.x,person.y).distance_to(target)<=GATHER_ASSIST_REACH:result.append(member)
	return result

func _finish_gather_work(region:String,tile:Vector2i,actor:String,continues:bool)->void:
	var place:=region+"/"+key(tile)
	if not continues:
		_gather_work.erase(place)
		return
	var now:=float(state.time)
	for previous:String in _gather_work.keys():
		var marks:Dictionary=_gather_work[previous]
		for member:String in marks.keys():
			if not active_tokens.has(member) or now>=float(marks[member]):marks.erase(member)
		if marks.is_empty():_gather_work.erase(previous)
	var recent:Dictionary=_gather_work.get(place,{})
	recent[actor]=now+GATHER_ASSIST_WINDOW
	_gather_work[place]=recent

## `view` (T046, optional): {"rect":Rect2i,"own":token,"layers":[names]} keeps only
## the rows of those layers that a view projection sends (view_projection.gd), chosen
## before the deep copy. `own` is the raw owner token. Empty: every row, as before.
func region_snapshot(region: String, omit_private_history:=false, recipient:="", view:Dictionary={}) -> Dictionary:
	if region not in REGIONS.ALL:return {}
	var result:=_region_snapshot_source(region,omit_private_history,recipient,view)
	var players := {}
	for token in state.players:
		if player_region(token)!=region:continue
		var person:Dictionary=state.players[token]
		if omit_private_history:
			person=person.duplicate()
			person.erase("receipts")
		players[token]=person
	result.players=players
	return result.duplicate(true)

## Build the regional layers before copying. Nested values can still belong to
## the world; a caller must copy them before editing or publishing them.
func _region_snapshot_source(region:String,omit_private_history:bool,recipient:String,view:Dictionary) -> Dictionary:
	var result := state.duplicate()
	result.erase("players")
	if region != _region:
		var layer_region := _region if region == REGIONS.HOME else region
		var layers: Dictionary = state.regions[layer_region]
		for field in REGIONS.LAYERS:result[field] = layers[field]
	if not view.is_empty():
		var positions:Variant=view.get("positions")
		for field:String in view.layers:
			if result.get(field) is Dictionary:result[field]=VIEW_PROJECTION.select(field,result[field],view.rect,view.own,positions)
	if omit_private_history:
		# History is fetched separately on demand. Keep it out of the deep copy
		# for broadcast snapshots while leaving canonical chest records untouched.
		result.objects=_objects_without_chest_history(result.objects,{})
	result.erase("regions")
	if region!=REGIONS.HOME:result.erase(WOODLAND.KEY)
	result.gather_drops={}
	var regional_drops:Dictionary=state.get("gather_drops",{}).get(region,{})
	for tile:String in regional_drops:
		var bundle:Dictionary=regional_drops[tile]
		var visible_bundle:Dictionary={"items":bundle.items,"ready_at":bundle.ready_at}
		if not recipient.is_empty():
			var reserved_for:=_gather_reservation_owner(bundle,float(state.time))
			if not reserved_for.is_empty() and reserved_for!=recipient and bundle.reserved==bundle.items:
				visible_bundle.public_at=float(bundle.ready_at)+GATHER_RESERVATION_SECONDS
		result.gather_drops[tile]=visible_bundle
	# Server-only undo history (raw tokens, record ids, inventory deltas).
	result.erase("construction")
	# T015 server-only transaction journal; players read it via ledger_view only.
	result.erase(TRANSACTION_LEDGER.STATE_KEY)
	result.erase(AUTUMN_FEAST.KEY)
	result.erase(WARM_LANTERN_NIGHT.KEY)
	result.erase(LANTERN_STROLL.KEY)
	result.erase(BEACH_TREASURE.KEY)
	result.erase(COOKING_RELAY.KEY)
	result.erase(LOST_CHICKS.KEY)
	result.erase(PARTY_CART.KEY)
	result.region_id = region
	result.stone_workshop_ready=STONE_WORKSHOP.has_station(home_layer("objects"))
	return result

func _objects_without_chest_history(objects:Dictionary, histories:Dictionary, keep_history_slot:=false) -> Dictionary:
	const FIELD:=SAVE_SCHEMA.CHEST_HISTORY.FIELD
	var projected:=objects
	for tile:String in objects:
		var entry:Dictionary=objects[tile]
		if not entry.has(FIELD):continue
		if histories.is_empty():projected=objects.duplicate()
		histories[tile]=entry[FIELD]
		var visible:=entry.duplicate()
		if keep_history_slot:visible[FIELD]=null
		else:visible.erase(FIELD)
		projected[tile]=visible
	return projected

const READ_ONLY_STEP_LAYERS:=["ground","roofs","edges"]

func _step_checkpoint() -> Dictionary:
	# Chest transfer rows are append-only and the journal replaces the array
	# when recording a transfer. A synchronous tick can retain the old arrays
	# while deep-copying the objects, inventories and other mutable state.
	var source:=state.duplicate()
	# Action receipts are only updated by act() and blueprint commits, outside
	# this synchronous tick. Keep them out of the rollback copy's deep traversal.
	source.players=state.players.duplicate()
	var receipts:Dictionary={}
	for token:String in source.players:
		var player:Dictionary=source.players[token]
		if not player.has("receipts"):continue
		receipts[token]=player.receipts
		player=player.duplicate()
		player.receipts=null
		source.players[token]=player
	var regions:Dictionary=state.regions.duplicate()
	var by_region:Dictionary={}
	# Building, door toggles, blueprint commits and undo write these layers
	# between ticks. step() only reads them and swaps their references between
	# regions. Remove a layer here before adding any tick-time writer for it.
	var shared_layers:Dictionary={}
	for region:String in REGIONS.ALL:
		var layer:Dictionary=source if region==REGIONS.HOME else regions[region]
		var histories:Dictionary={}
		var objects:=_objects_without_chest_history(layer.objects,histories,true)
		var held:Dictionary={}
		for field:String in READ_ONLY_STEP_LAYERS:
			var cells:Dictionary=layer[field]
			if not cells.is_empty():held[field]=cells
		if histories.is_empty() and held.is_empty():continue
		if region!=REGIONS.HOME:
			layer=layer.duplicate()
			regions[region]=layer
		if not histories.is_empty():
			by_region[region]=histories
			layer.objects=objects
		if not held.is_empty():
			shared_layers[region]=held
			for field:String in held:layer[field]={}
	source.regions=regions
	var checkpoint:=source.duplicate(true)
	for region:String in shared_layers:
		var target:Dictionary=checkpoint if region==REGIONS.HOME else checkpoint.regions[region]
		for field:String in shared_layers[region]:target[field]=shared_layers[region][field]
	for token:String in receipts:checkpoint.players[token].receipts=receipts[token]
	for region:String in by_region:
		var layer:Dictionary=checkpoint if region==REGIONS.HOME else checkpoint.regions[region]
		for tile:String in by_region[region]:
			layer.objects[tile][SAVE_SCHEMA.CHEST_HISTORY.FIELD]=by_region[region][tile]
	return checkpoint

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
func order_board(token: String,channel:="village") -> Dictionary:
	return order_boards(token,[channel]).get(channel,{})

func order_boards(token:String,channels:Array[String]) -> Dictionary:
	var person: Dictionary = state.players.get(token, {})
	if person.is_empty():return {}
	var now := float(state.time)
	var contexts:=ORDER_CATALOG.contexts_from_world(self,token,channels)
	var boards:={}
	for channel in channels:
		var view:=ORDER_CATALOG.snapshot(person.get("orders",{}),now,contexts[channel])
		view.board=state.get("board",false)==true
		boards[channel]=view
	return boards

## T071 市集攤位格（可用在用戶端的家園快照上）；全被佔用時為 MARKET.NO_CELL。
static func market_cell(snapshot: Dictionary) -> Vector2i:
	return MARKET.cell_for(snapshot)

## T071 只給本人看的攤位摘要（Session 以 data.own_market 送出）。
func market_view(token: String) -> Dictionary:
	var view:=MARKET.view(state,token)
	var person:Dictionary=state.players.get(token,{})
	if view.get("unlocked",false) and person.has("market_decor"):
		view.decor=MARKET_DECOR.style(person)
	if view.get("unlocked",false) and RESIDENT_GOALS.done(person,"xiaoli").has(3):view.xiaoli_decor_reward=true
	return view

## C12 D14 夏季市集：本人的試吃摘要（Session 以 data.own_summer_market 送出）。
func summer_market_view(token: String) -> Dictionary:
	return SUMMER_MARKET.view(state,token,NAMES)

## D14 on the host: true when this player has learned 彩虹蔬菜串 at the 夏季市集 (persistent).
static func summer_market_known(person: Dictionary) -> bool:
	return SUMMER_MARKET.recipe_known(person)

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
func souvenir_view(token: String,placements:Variant=null) -> Dictionary:
	return SOUVENIR.view(state,token,placements)

func swap_region_layers(region: String) -> void:
	var other: Dictionary = state.regions[region]
	for field in REGIONS.LAYERS:
		var value = state[field]
		state[field] = other[field]
		other[field] = value

func _regional_guest(actor:String,public_id:String) -> String:
	for guest:String in regional_tokens():
		if guest!=actor and guest.sha256_text().left(16)==public_id:return guest
	return ""

func regional_tokens() -> Array:
	return active_tokens.keys().filter(func(token): return player_region(token) == _region)

const REST_DAWN := 360.0
const REST_STEP := 1.0

func night_rest_reason(token:String) -> String:
	var person:Dictionary=state.players.get(token,{})
	if person.is_empty():return "請先進入島上。"
	var region:=player_region(token)
	var cell:=Vector2i(floori(person.x),floori(person.y))
	if region in MINES.IDS or (region==WARM_SPRINGS.REGION and WARM_SPRINGS.POOLS.upland.water.grow(3).has_point(cell)):
		return "請先離開礦道或高地冷泉，再休息。"
	if person.has(RESIDENT_GOALS.VOYAGE_START) or not person.get("fishing",{}).is_empty():
		return "請先靠岸或收起釣竿，再休息。"
	if TRADE.blocks_sleep(trade_offers):return "請先結束島民交換。"
	if state.get("festival",{}).get("active",false):return "請先完成風鈴接力。"
	for activity:Dictionary in [HARVEST.round_state(state),FISH_MEET.round_state(state),SHOWCASE.round_state(state)]:
		if activity.active and activity.participants.get(token,{}).get("joined",false):
			return "請先退出正在參加的活動。"
	if fposmod(float(state.time),WEATHER.DAY_SECONDS)>=REST_DAWN:return "午夜 00:00 後才可休息到清晨。"
	return ""

func rest_until_dawn(token:String) -> Dictionary:
	var reason:=night_rest_reason(token)
	if not reason.is_empty():return fail(reason)
	switch_region(REGIONS.HOME)
	var before:=state.duplicate(true)
	var before_undo:=_undo_ticks_at.duplicate(true)
	var dawn:=floorf(float(state.time)/WEATHER.DAY_SECONDS)*WEATHER.DAY_SECONDS+REST_DAWN
	# Resume the same world systems across the skipped interval without writing
	# intermediate states. The final save commits the morning and its outputs together.
	while float(state.time)<dawn:
		var interval:=minf(REST_STEP,dawn-float(state.time))
		if not step(interval,true,false):
			_step_rollback(before,before_undo,step_error)
			return fail("這一晚無法結算，時間與進度已保留。")
	state.committed+=1
	if not save():
		_step_rollback(before,before_undo,STEP_FAIL_SAVE)
		return fail("無法保存清晨進度，時間與進度已保留。")
	return ok("早安！已休息到 06:00，農田與設備已結算。")

func step(dt: float, active: bool, persist:bool=true) -> bool:
	gather_pickup_events.clear()
	step_error = ""
	if not active:return true
	# Atomic tick: `before` is taken HOME-oriented (regional layers inside
	# state.regions), so _restore(before) -- which also resets _region to HOME --
	# always yields a consistently loaded projection. The loop below ends in
	# HOME anyway, so a successful tick is unchanged by this normalisation.
	switch_region(REGIONS.HOME)
	var before := _step_checkpoint()
	var undo_ticks_before := _undo_ticks_at.duplicate(true)
	var start: float = state.time
	var now:=start+dt
	var changed := false
	_undo_used = {}
	for region in REGIONS.ALL:
		if region==PARTY_CART.REGION:continue
		if region!=REGIONS.HOME:
			var layers:Dictionary=state.regions[region]
			if _idle_region(layers,region):
				_advance_idle_region(layers,now)
				continue
		switch_region(region)
		state.time = start
		var local_changed := step_region(dt)
		changed = changed or local_changed
	switch_region(REGIONS.HOME)
	if WOODLAND.advance(self):changed=true
	# A crowded plaza may have had no table space when the picnic finished.
	var table_record:Variant=state.get("community")
	if state.picnic and table_record is Dictionary and str(table_record.get("table","")).is_empty():
		var table:=COMMUNITY.choose_table(state,active_tokens)
		if not table.is_empty():
			table_record.table=table
			changed=true
	aru_bench_prune() # transient seats: drop stale sitters (stood/walked/travelled/offline), never saved
	if state.animal.has(CHICKEN_CUDDLE.FIELD) and (not active_tokens.has(str(state.animal[CHICKEN_CUDDLE.FIELD])) or CHICKEN_CUDDLE.holder(state,active_tokens).is_empty()):
		CHICKEN_CUDDLE.clear(state.animal)
		changed=true
	if state.animal.has(CHICKEN_FEED_FOLLOW.FIELD) and CHICKEN_FEED_FOLLOW.holder(state,active_tokens).is_empty():
		state.animal.erase(CHICKEN_FEED_FOLLOW.FIELD)
		changed=true
	if state.livestock.get("cow",{}).has(COW_CARE.FIELD) and COW_CARE.active_actor(state,active_tokens).is_empty():
		COW_CARE.clear(state)
		changed=true
	for token:String in state.players:
		var sailor:Dictionary=state.players[token]
		if not sailor.has(RESIDENT_GOALS.VOYAGE_START):continue
		if not active_tokens.has(token):
			sailor.erase(RESIDENT_GOALS.VOYAGE_START)
			sailor.erase(RESIDENT_GOALS.VOYAGE_CAPTAIN)
			changed=true
		elif float(state.time)-float(sailor[RESIDENT_GOALS.VOYAGE_START])>=RESIDENT_GOALS.VOYAGE_SECONDS:
			sailor.erase(RESIDENT_GOALS.VOYAGE_START)
			sailor.erase(RESIDENT_GOALS.VOYAGE_CAPTAIN)
			sailor[RESIDENT_GOALS.VOYAGE_DONE]=true
			changed=true
	var freight_changed := MINE_FREIGHT.step(state)
	var auto_changed:=MINE_AUTO_FREIGHT.step(state)
	var tea_changed:=TEA_CERAMICS.step(state)
	var market_changed:=MARKET.step(state)
	if market_changed:
		for obj:Dictionary in state.objects.values():
			if obj.get("type")==INDUSTRY.COAST_CART and obj.has("market_cart_open") and not MARKET.record(state.players.get(obj.owner,{})).pending:
				obj.erase("market_cart_open")
	if HARVEST.step(state,active_tokens):market_changed=true # T071 豐收接力：離線放下、時間到結算
	if FISH_MEET.step(state,active_tokens):market_changed=true # T071 河岸釣魚會：離線退出、時間到結算
	if SHOWCASE.step(state,active_tokens):market_changed=true # T071 家園布置題：離線退出、時間到結算、冷卻後清空展示
	if BEACH_TREASURE.step(state):market_changed=true
	if COOKING_RELAY.step(state):market_changed=true
	if PARTY_CART.step(state,active_tokens):market_changed=true
	if LANTERN_STROLL.step(state,active_tokens):market_changed=true
	if LOST_CHICKS.step(state,active_tokens,_activity_can_step,false):market_changed=true
	var livestock_changed:=LIVESTOCK.step(state.livestock,float(state.time),state.objects,dt)
	var automatic_collected:=AnimalCollector.step(self)
	for tile in automatic_collected:_undo_mark_remote_chest(_undo_used,REGIONS.HOME,{"cell":tile})
	livestock_changed=livestock_changed or not automatic_collected.is_empty()
	var chicken_changed:=_store_chicken_egg()
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
	if persist and (changed or freight_changed or auto_changed or tea_changed or salt_changed or undo_changed or livestock_changed or market_changed or chicken_changed):
		state.committed += 1
		if not save():
			_step_rollback(before,undo_ticks_before,STEP_FAIL_SAVE)
			return false
	if not _meadow_round.is_empty():
		_meadow_round=MEADOW_ADVENTURE.step(_meadow_round,_meadow_adventurers(),float(state.time))
	for token:String in _shy_spores.keys():
		if not active_tokens.has(token) or player_region(token)!=SHY.REGION:
			_shy_spores.erase(token)
			continue
		var person:Dictionary=state.players[token]
		var run:=SHY_SPORES.step(_shy_spores[token],Vector2(person.x,person.y),float(state.time))
		if run.is_empty():_shy_spores.erase(token)
		else:_shy_spores[token]=run
	for token:String in _guardian_trials.keys():
		if not active_tokens.has(token) or player_region(token)!=GUARDIAN.REGION:
			_guardian_trials.erase(token)
			continue
		var person:Dictionary=state.players[token]
		var run:=GUARDIAN_TRIAL.step(_guardian_trials[token],Vector2(person.x,person.y),float(state.time))
		if run.is_empty():_guardian_trials.erase(token)
		else:_guardian_trials[token]=run
	_prune_undo_ticks()
	return true

## Restores a failed tick: HOME-oriented state snapshot (also _region=HOME),
## same-process undo ticks and the per-tick dependency scratch.
func _step_rollback(before: Dictionary, undo_ticks_before: Dictionary, code: String) -> void:
	_restore(before)
	_undo_ticks_at = undo_ticks_before
	_undo_used = {}
	gather_pickup_events.clear()
	step_error = code

func _store_chicken_egg() -> bool:
	return LIVESTOCK.store_chicken_cycle(state.animal,state.animal,"basket_eggs",EGG_BASKET_CAPACITY,float(state.time))>0

static func chicken_status(animal:Dictionary,now:float) -> String:
	var stored:=int(animal.get("basket_eggs",0))
	if stored>=EGG_BASKET_CAPACITY:return "收集籃已滿，先收蛋再餵食。"
	var due:=float(animal.get("egg_ready",-1))
	if due>=0.0:
		if now>=due:return "有一顆雞蛋等著你！"
		return "糯米雞正在休息，約 %d 秒後下蛋。"%ceili(due-now)
	return "糯米雞想吃一份飼料。"

func pump_rate() -> int:
	return pump_rate_for(_region,state)

static func pump_rate_for(region:String,snapshot:Dictionary)->int:
	if region==REGIONS.LANYANG and snapshot.get("lanyang_life",{}).get("repaired",false):
		return LANYANG_LIFE.REPAIRED_PUMP_RATE
	return INDUSTRY.PUMP_RATE

func _idle_region(layers:Dictionary,region:String) -> bool:
	return layers.objects.is_empty() and layers.crops.is_empty() and layers.forest.is_empty() and state.get("gather_drops",{}).get(region,{}).is_empty()

static func _advance_idle_region(layers:Dictionary,now:float) -> void:
	# Keep the first device's usual cadence if a player builds here later.
	if now>=float(layers.next_network_check):layers.next_network_check=now+INDUSTRY.INTERVAL
	if now>=float(layers.next_logistics_check):layers.next_logistics_check=now+LOGISTICS.INTERVAL

## These jobs share one pass over furniture. Keep insertion order and the
## live device records. Network routing and logistics still use the full map.
func _step_devices(objects:Dictionary) -> Dictionary:
	const ACTIVE_TYPES:=["forester","waterworks","mine_drill"]
	var devices:Dictionary={}
	for k:String in objects:
		var obj:Dictionary=objects[k]
		var kind:Variant=obj.get("type")
		if kind in ACTIVE_TYPES or INDUSTRY.SPRINKLER_CAPACITIES.has(kind) or obj.has("cooking") or obj.has("processing"):
			devices[k]=obj
	return devices

func step_region(dt: float) -> bool:
	var now:=float(state.time)+dt
	if _idle_region(state,_region):
		_advance_idle_region(state,now)
		state.time=now
		return false
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
	var devices:=_step_devices(state.objects)
	var pending:=pending_sprinklers(now,water_plan,devices)
	var forestry_due:=FORESTRY.due({"objects":devices},now)
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
	var logistics_history:Array=[]
	var logistics_plan:=LOGISTICS.plan(self,now,logistics_due,logistics_history)
	if not logistics_plan.is_empty():
		var used_here:Dictionary=_undo_used.get(_region,{})
		for device_key in logistics_plan:used_here[device_key]=true
		_undo_used[_region]=used_here
	for device_key in logistics_plan:
		var device:Dictionary=state.objects[device_key]
		var updated:Dictionary=logistics_plan[device_key]
		device.clear()
		device.merge(updated)
	LOGISTICS.record_history(state.objects,logistics_history,state.time)
	var drill_changed:=MINE_DRILL.tick(devices,state.mine_depths,_region,now)
	var waterworks_changed:=WATERWORKS.tick(devices,now)
	var all_active := active_tokens
	active_tokens = {}
	for token in all_active:
		if player_region(token) == _region:active_tokens[token] = true
	var forest_work:=FORESTRY.cycle(self,forestry_due)
	active_tokens = all_active
	var cooking_changed:=step_cooking(now,devices)
	var processing_changed:=step_processing(now,devices)
	var picked_up:=_collect_gather_drops(now)
	return picked_up or crops_weathered or watered or not water_plan.is_empty() or forest_work or waterworks_changed or drill_changed or not logistics_plan.is_empty() or cooking_changed or processing_changed

func _drop_gather_items(token:String,tile:String,items:Dictionary) -> bool:
	var all_drops:Dictionary=state.get("gather_drops",{})
	var drops:Dictionary=all_drops.get(_region,{})
	var previous:Dictionary=drops.get(tile,{})
	var now:=float(state.time)
	var reserved_for:=_gather_reservation_owner(previous,now)
	if not reserved_for.is_empty() and reserved_for!=token:return false
	var reserved:Dictionary=previous.get("reserved",{}).duplicate() if not reserved_for.is_empty() else {}
	var contents:Dictionary=previous.get("items",{}).duplicate()
	for item:String in items:
		var total:=int(contents.get(item,0))+int(items[item])
		if not ITEM_CATALOG.can_hold(item,total):return false
		contents[item]=total
		reserved[item]=int(reserved.get(item,0))+int(items[item])
	drops[tile]={"items":contents,"ready_at":now+GATHER_DROP_DELAY,"reserved_for":token,"reserved":reserved}
	all_drops[_region]=drops
	state.gather_drops=all_drops
	return true

func _gather_reservation_owner(bundle:Dictionary,now:float) -> String:
	return str(bundle.get("reserved_for","")) if now<float(bundle.get("ready_at",0.0))+GATHER_RESERVATION_SECONDS else ""

func _collect_gather_drops(now:float) -> bool:
	var all_drops:Dictionary=state.get("gather_drops",{})
	var drops:Dictionary=all_drops.get(_region,{})
	if drops.is_empty():return false
	var changed:=false
	for token:String in regional_tokens():
		var person:Dictionary=state.players[token]
		if person.has(RESIDENT_GOALS.VOYAGE_START):continue
		var position:=Vector2(person.x,person.y)
		var nearest:=Vector2i(position.floor())
		var inventory:Dictionary=person.inventory
		for y in range(nearest.y-1,nearest.y+2):
			for x in range(nearest.x-1,nearest.x+2):
				var tile:=Vector2i(x,y)
				var tile_key:=key(tile)
				var bundle:Dictionary=drops.get(tile_key,{})
				if bundle.is_empty() or now<float(bundle.ready_at):continue
				if position.distance_squared_to(Vector2(tile)+Vector2(0.5,0.5))>GATHER_PICKUP_RADIUS*GATHER_PICKUP_RADIUS:continue
				var collected:Dictionary={}
				var reserved_for:=_gather_reservation_owner(bundle,now)
				var reserved:Dictionary=bundle.get("reserved",{})
				for item:String in bundle.items.keys():
					var available:=int(bundle.items[item])
					if not reserved_for.is_empty() and reserved_for!=token:available-=int(reserved.get(item,0))
					var count:=mini(available,ITEM_CATALOG.saved_count_limit(item)-int(inventory.get(item,0)))
					if count<=0:continue
					give(inventory,item,count)
					collected[item]=count
					bundle.items[item]=int(bundle.items[item])-count
					if reserved_for==token and reserved.has(item):
						var left:=int(reserved[item])-count
						if left>0:reserved[item]=left
						else:reserved.erase(item)
					if bundle.items[item]==0:bundle.items.erase(item)
				if collected.is_empty():continue
				if reserved_for.is_empty() or reserved.is_empty():
					bundle.erase("reserved_for")
					bundle.erase("reserved")
				if bundle.items.is_empty():drops.erase(tile_key)
				gather_pickup_events.append({"token":token,"tile":tile,"items":collected})
				changed=true
	if drops.is_empty():
		all_drops.erase(_region)
		if all_drops.is_empty():state.erase("gather_drops")
	return changed

## T039: advances every plot of the current region projection over world time
## [start, start+dt] using WEATHER's calendar-day rule (wetness ends at each game
## midnight; exposed plots are re-wetted by rain; growth only while wet, capped at
## maturity). Exposed = outdoor region and no roof on the tile, evaluated per tick
## so roof placement/removal applies on the next tick. Rain never consumes
## sprinkler water nor credits irrigation. Machines/queues keep their own dt
## rules; only crops are segmented by day here. Returns true when any plot's wet
## flag flipped, so rain/drying transitions are saved (or rolled back with step).
static func supply_box_unlocked(person:Dictionary,bobo_completed:=false) -> bool:
	return exploration_level(exploration_points(person))>=SUPPLY_BOX_LEVEL or bobo_completed or RESIDENT_GOALS.done(person,"bobo").has(3)

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
static func milu_recipe_cell(snapshot:Dictionary,site:String) -> Vector2i:
	match site:
		"board":return Vector2i(40,29)
		"shop":return Village.resident_cell(snapshot,"xiaoli")
		"table":
			if snapshot.get("picnic",false):return COMMUNITY.table_cell(snapshot)
	return COMMUNITY.NO_CELL

static func achao_route_cell(site:String) -> Vector2i:
	match site:
		"board":return Vector2i(40,29)
		"ferry":return TRANSIT.POINTS[REGIONS.HOME].ferry.cell
		"river":return FISH_MEET.SIGN
	return Vector2i(-1,-1)

func _shared_garden_choose(token:String,player:Dictionary,choice:String) -> Dictionary:
	var goals:=RESIDENT_GOALS
	var pots:Array=state.get(goals.GARDEN_KEY,[])
	if pots.size()>=goals.GARDEN_POTS.size():return fail("三盆花都選好了，可以向星禾回報。")
	var helper:=goals.GARDEN_NPCS.has(choice)
	var stage:=RESIDENT_BOND.stage(player,"xinghe")
	if stage<4 and (pots.is_empty() or helper):return fail("先請星禾的好友來開啟共同花園。")
	if not helper and choice not in goals.GARDEN_FLOWERS:return fail("請從三種花裡挑一種。")
	var author:=choice if helper else token
	for pot:Dictionary in pots:
		if pot.npc==helper and pot.author==author:return fail("這位作者已經選過一盆了。")
	var flower:String=goals.GARDEN_NPCS[choice].flower if helper else choice
	pots.append({"npc":helper,"author":author,"flower":flower})
	state[goals.GARDEN_KEY]=pots
	return ok("三盆花都選好了，去找星禾掛上花園牌。" if pots.size()==goals.GARDEN_POTS.size() else "花盆已放好，花園記下了選花的人。")

func _achao_voyage(token:String,player:Dictionary,cell:Vector2i,operation:String) -> Dictionary:
	var goals:=RESIDENT_GOALS
	if operation=="photo":
		if not player.has(goals.VOYAGE_START) or RESIDENT_BOND.stage(player,"achao")<4:
			return fail("和阿潮成為好友後，在航行中才能拍合照。")
		player[goals.VOYAGE_PHOTO]=true
		return ok("合照已記在手帳，回到碼頭後可找阿潮。")
	if operation=="return":
		if not player.has(goals.VOYAGE_START):return fail("小船已停在碼頭。")
		player.erase(goals.VOYAGE_START)
		player.erase(goals.VOYAGE_CAPTAIN)
		for sailor:Dictionary in state.players.values():
			if sailor.get(goals.VOYAGE_CAPTAIN)==token:
				sailor.erase(goals.VOYAGE_CAPTAIN)
				sailor.erase(goals.VOYAGE_START)
		return ok("已返回碼頭，想再出發時可以找阿潮。")
	if _region!=REGIONS.HOME or cell!=RESIDENT_BOND.dock_cell(state) or RESIDENT_BOND.stage(player,"achao")<3:
		return fail("取得阿潮的信任後，到風鈴渡口碼頭找他。")
	if player.has(goals.VOYAGE_START):return fail("小船已經出發。")
	if not TRANSIT.boat_open(state):return fail("先到公告板完成碼頭與小船工程。")
	match operation:
		"repair":
			if state.get(goals.DOCK_LIGHT,false):return fail("碼頭燈已經亮起來了。")
			for item:String in goals.VOYAGE_LIGHT_COST:
				if int(player.inventory.get(item,0))<int(goals.VOYAGE_LIGHT_COST[item]):return fail("修燈需要 4 份木材和 1 份銅礦。")
			for item:String in goals.VOYAGE_LIGHT_COST:give(player.inventory,item,-int(goals.VOYAGE_LIGHT_COST[item]))
			state[goals.DOCK_LIGHT]=true
			return ok("碼頭燈重新亮起來了。")
		"join":
			var occupied:Dictionary={}
			for sailor:Dictionary in state.players.values():
				if sailor.has(goals.VOYAGE_CAPTAIN):occupied[sailor[goals.VOYAGE_CAPTAIN]]=true
			for captain:String in active_tokens:
				var vessel:Dictionary=state.players[captain]
				if captain==token or occupied.has(captain) or not vessel.has(goals.VOYAGE_START) or vessel.has(goals.VOYAGE_CAPTAIN):continue
				var started:=float(vessel[goals.VOYAGE_START])
				if float(state.time)-started>goals.VOYAGE_BOARD_WINDOW:continue
				player.erase("fishing")
				player[goals.VOYAGE_START]=started
				player[goals.VOYAGE_CAPTAIN]=captain
				return ok("你坐上朋友的小船。")
			return fail("沒有空船位，請在朋友出航後五秒內加入。")
		"depart":
			if not state.get(goals.DOCK_LIGHT,false):return fail("先修好碼頭燈，再出發試航。")
			player.erase("fishing")
			player[goals.VOYAGE_START]=float(state.time)
			return ok("小船出發。按返回鍵或互動鍵可提前返航。")
		"paint":
			if not goals.done(player,"achao").has(3):return fail("先完成阿潮的試航事件。")
			if player.get(goals.VOYAGE_PAINT,false):player.erase(goals.VOYAGE_PAINT)
			else:player[goals.VOYAGE_PAINT]=true
			return ok("已換成藍白船身。" if player.has(goals.VOYAGE_PAINT) else "已換回原木船身。")
	return fail("無法辨識這次試航操作。")

## Legacy (pre-scene) check; Session now reads the real scene. Kept only for external callers.
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

## Flour still on offer for this account today (0..FLOUR_DAILY). Pure read: a missing or past-day record
## (old save, new world day) means a full shelf; a malformed record means nothing is on offer.
static func flour_left(player:Dictionary,now:float) -> int:
	var row:Variant=player.get(SAVE_SCHEMA.FLOUR_STALL_KEY)
	if row==null:return FLOUR_DAILY
	if not row is Dictionary or not row.get("day") is int or not row.get("bought") is int:return 0
	if int(row.day)!=int(WEATHER.day_index(now)):return FLOUR_DAILY
	return clampi(FLOUR_DAILY-int(row.bought),0,FLOUR_DAILY)

## Sugar still on offer for this account today (0..SUGAR_DAILY); same read rules as flour_left().
static func sugar_left(player:Dictionary,now:float) -> int:
	var row:Variant=player.get(SAVE_SCHEMA.SUGAR_STALL_KEY)
	if row==null:return SUGAR_DAILY
	if not row is Dictionary or not row.get("day") is int or not row.get("bought") is int:return 0
	if int(row.day)!=int(WEATHER.day_index(now)):return SUGAR_DAILY
	return clampi(SUGAR_DAILY-int(row.bought),0,SUGAR_DAILY)

static func _record_crop_sale(player:Dictionary,item:String) -> void:
	if CROPS.has(CROP_CATALOG.base_kind(item)) and not player.has(RESIDENT_GOALS.CROP_TRADE_KEY):
		player[RESIDENT_GOALS.CROP_TRADE_KEY]=RESIDENT_GOALS.CROP_SOLD

static func crop_detail_points(snapshot:Dictionary,actor:String,at:Vector2,region:String)->Dictionary:
	var crops:Dictionary=snapshot.get("crops",{})
	if crops.is_empty() or region==FLOWER_NURSERY.REGION:return {}
	var sketches:Dictionary=snapshot.get("own_crop_sketches",{})
	var seek_sketches:bool=region==REGIONS.HOME and int(snapshot.get("resident_bonds",{}).get("diandian",{}).get("stage",0))>=1 and sketches.size()<RESIDENT_GOALS.SKETCH_TARGET
	var reach:=Vector2(3.2,3.2)
	var first:Vector2i=Vector2i((at-reach).floor())
	var last:Vector2i=Vector2i((at+reach).floor())
	var points:Dictionary={}
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var cell:=Vector2i(x,y)
			var plot_key:=key(cell)
			if not crops.has(plot_key):continue
			var crop:Dictionary=crops[plot_key]
			var kind:String=crop.get("kind","")
			if crop.get("owner","")==actor or (seek_sketches and CROPS.has(kind) and not sketches.has(kind)):
				points["plot:"+plot_key]=Vector2(cell)+Vector2(0.5,0.5)
	return points

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
static func plot_dormant(crop:Dictionary, roof:Dictionary, region:String, tile:Vector2i, time:float, sealed_glass:=false) -> bool:
	var kind:=str(crop.get("kind",""))
	if not CROPS.has(kind) or float(crop.get("growth",0.0))>=float(CROPS[kind].time):return false
	if str(roof.get("type",""))==GREENHOUSE_GLASS.LEGACY_ROOF or sealed_glass:return false
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
	return crop_terrain_problem(kind,tile,_region)

static func crop_terrain_problem(kind:String,tile:Vector2i,region:String)->String:
	if kind=="mist_tea" and (region!=REGIONS.Bamboo.REGION or not REGIONS.Bamboo.TEA_BEDS.has_point(tile)):
		return "霧竹茶要種在溪谷茶圃"
	if region==REGIONS.Bamboo.REGION and kind!="mist_tea":return "溪谷茶圃只種霧竹茶"
	if kind=="rice" and not REGIONS.rice_paddy(tile,region):
		return "月牙稻米要種在宜蘭水圳旁的水田"
	if kind=="star_mushroom" and region!="mine_5":
		return "星夜菇要種在金瓜石第五層的洞內菌床"
	return ""

func greenhouse_covers(tile_key:String,memo:Variant=null) -> bool:
	return GREENHOUSE_GLASS.covered(state,tile_key,memo)

func has_glass_roof(tile_key:String)->bool:
	return GREENHOUSE_GLASS.is_glass(state.roofs.get(tile_key,{}).get("type",""))

func step_crop_weather(start:float,dt:float) -> bool:
	var changed:=false
	var indoor:=WEATHER.is_indoor(_region)
	var in_nursery:=_region==FLOWER_NURSERY.REGION
	var glass_memo:Dictionary={}
	var tick_start:=WEATHER.safe_time(start)
	var tick_end:=tick_start+dt
	var day:=WEATHER.day_index(tick_start)
	var day_elapsed:=0.0
	if is_finite(tick_end) and tick_end<(day+1.0)*WEATHER.DAY_SECONDS:
		day_elapsed=maxf(0.0,tick_end-tick_start)
	var season:=WEATHER.season_on_day(day)
	var raining:=not indoor and WEATHER.outdoor_id(day)=="rainy"
	for k in state.crops:
		var crop=state.crops[k]
		if not crop is Dictionary:continue
		var roofed:bool=state.roofs.has(k)
		# The cooperative nursery's teaching beds support its three flowers
		# year-round. Home plots still follow each crop's outdoor season.
		var year_round:bool=(in_nursery and nursery_grows_year_round(str(crop.get("kind","")),_region,cell(k))) or (roofed and greenhouse_covers(k,glass_memo))
		if _advance_crop_weather(crop,not indoor and not roofed,start,dt,year_round,day_elapsed,season,raining):changed=true
	for box_key in state.objects:
		var box:Dictionary=state.objects[box_key]
		if not box.has(NURSERY_BOX.SLOTS):continue
		for slot:String in box[NURSERY_BOX.SLOTS]:
			var crop:Dictionary=box[NURSERY_BOX.SLOTS][slot]
			if crop.kind=="":continue
			var plot_key:=key(NURSERY_BOX.plot_cell(cell(box_key),int(slot),INDUSTRY.is_vertical(box)))
			if _advance_crop_weather(crop,not indoor and not state.roofs.has(plot_key),start,dt,greenhouse_covers(plot_key,glass_memo),day_elapsed,season,raining):changed=true
	return changed

static func _advance_crop_weather(crop:Dictionary,exposed:bool,start:float,dt:float,year_round:bool,
	day_elapsed:float,season:String,raining:bool)->bool:
	var kind:=str(crop.get("kind",""))
	var need:=float(CROPS[kind].time) if CROPS.has(kind) else 0.0
	var was_wet:bool=crop.get("wet",false)==true
	var growth:=float(crop.get("growth",0.0))
	var seasons:Array=CROP_SEASONS.get(kind,[])
	if day_elapsed>0.0:
		var wet:=was_wet or (exposed and raining)
		if need>0.0:crop.growth=WEATHER.grow_during_day(growth,need,day_elapsed,season,seasons,year_round) if wet else growth
		if wet==was_wet:return false
		crop.wet=wet
		return true
	var result:Dictionary=WEATHER.advance_plot(was_wet,exposed,growth,need,start,dt,seasons,year_round)
	if need>0.0:crop.growth=float(result.growth)
	if bool(result.wet)==was_wet:return false
	crop.wet=bool(result.wet)
	return true

func can_harvest_plot(plot:Dictionary,token:String,machine:=false) -> bool:
	if plot.get("owner","")==token:return true
	if _region==FLOWER_NURSERY.REGION:return false
	var access:String=plot.get("harvest_access","owner" if machine else "island")
	return access=="island" or (access=="friend" and plot.get("harvest_friend","")==token)

func _blocks_sprinkler(tile:Vector2i) -> bool:
	var obj:Dictionary=state.objects.get(key(tile),{})
	var kind:String=obj.get("type","")
	return kind in ["wall","window"] or (kind=="door" and not obj.get("open",false))

func _edge_blocks_sprinkler(from:Vector2i,step:Vector2i) -> bool:
	if state.edges.is_empty():return false
	var id:=EDGE_GRID.key(from,EDGE_GRID.DIRS.find(step),SIZE)
	var barrier:Dictionary=state.edges.get(id,{})
	return not barrier.is_empty() and (barrier.get("type")!="edge_door" or not barrier.get("open",false))

func _sprinkler_reaches(origin:Vector2i, offset:Vector2i) -> bool:
	# Trace from tile center to tile center. When the ray hits a corner,
	# either of the two adjoining tiles can block it.
	var span:=offset.abs()
	var direction:=offset.sign()
	var crossed:=Vector2i.ZERO
	var tile:=origin
	while crossed!=span:
		var x_cross:=(2*crossed.x+1)*span.y
		var y_cross:=(2*crossed.y+1)*span.x
		var step_x:=crossed.x<span.x and (crossed.y==span.y or x_cross<=y_cross)
		var step_y:=crossed.y<span.y and (crossed.x==span.x or y_cross<=x_cross)
		var horizontal:=Vector2i(direction.x,0)
		var vertical:=Vector2i(0,direction.y)
		if step_x and _edge_blocks_sprinkler(tile,horizontal):return false
		if step_y and _edge_blocks_sprinkler(tile,vertical):return false
		if step_x and step_y:
			if _blocks_sprinkler(tile+horizontal) or _blocks_sprinkler(tile+vertical):return false
			if _edge_blocks_sprinkler(tile+horizontal,vertical) or _edge_blocks_sprinkler(tile+vertical,horizontal):return false
		var step:=Vector2i(int(step_x),int(step_y))
		crossed+=step
		tile+=step*direction
		if _blocks_sprinkler(tile):return false
	return true

func pending_sprinklers(now:float,water_plan:Dictionary,devices:Variant=null) -> Dictionary:
	var pending:Dictionary={}
	var objects:Dictionary=state.objects if devices==null else devices
	for k in objects:
		var device:Dictionary=objects[k]
		if not INDUSTRY.SPRINKLER_CAPACITIES.has(device.type) or not device.enabled or int(water_plan.get(k,device.water))==0 or float(device.next_water)>now:
			continue
		var targets:Array[String]=[]
		var origin:=cell(k)
		for offset in INDUSTRY.sprinkler_offsets(device.type):
			if device.get("sprinkler_daily",false) and not _sprinkler_reaches(origin,offset):continue
			var crop_key:=key(origin+offset)
			var crop:Dictionary=state.crops.get(crop_key,{})
			if crop.get("kind","")!="" and not crop.get("wet",false) and crop.get("owner","")==device.owner:
				targets.append(crop_key)
		pending[k]=targets
	return pending

func step_sprinklers(pending:Dictionary) -> bool:
	var watered:=false
	for k in pending:
		var device:Dictionary=state.objects[k]
		var used:=false
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
			used=true
		if device.get("sprinkler_daily",false):
			if used:
				device.next_water=(floorf(float(state.time)/WEATHER.DAY_SECONDS)+1.0)*WEATHER.DAY_SECONDS
		else:
			device.next_water=float(state.time)+SPRINKLER_INTERVAL
	return watered

# ---------------------------------------------------------------------------
# T036 stove cooking queue (optional stove field `cooking`, CookingQueue state).
# A stove carries either the legacy single `job` or `cooking`, never both.
# ---------------------------------------------------------------------------

## Advances every queue-enabled stove of the current region projection to
## world time `now`. Malformed queues are left untouched (never replaced).
## Each stove that completed work is recorded as used for construction undo.
func step_cooking(now: float,devices:Variant=null) -> bool:
	var changed:=false
	var objects:Dictionary=state.objects if devices==null else devices
	for k in objects:
		var stove=objects[k]
		if not stove is Dictionary or not INDUSTRY.is_stove(str(stove.get("type",""))) or not stove.has("cooking"):continue
		if stove.has("job") or not stove.cooking is Dictionary:continue
		var advanced:Dictionary=COOKING_QUEUE.advance(stove.cooking,RECIPES,now)
		if not advanced.ok or not advanced.changed:continue
		stove.cooking=advanced.state
		var used_here:Dictionary=_undo_used.get(_region,{})
		used_here[k]=true
		# C12: the whole 2x2 footprint is one used object, so an undo watching any of its four cells closes.
		if stove.type==INDUSTRY.KITCHEN_STOVE:
			for c in KITCHEN_STOVE.cells_at(cell(k)):used_here[key(c)]=true
		_undo_used[_region]=used_here
		changed=true
	return changed

## T036 manual sawmill/charcoal-kiln queues (optional device.processing).
## Same contract as step_cooking with the station-filtered INDUSTRY.PROCESS
## catalog. Invalid coexistence (job / auto mode) or malformed queues are left
## untouched. Completions mark the device used for construction undo.
func step_processing(now: float,devices:Variant=null) -> bool:
	var changed:=false
	var objects:Dictionary=state.objects if devices==null else devices
	for k in objects:
		var device=objects[k]
		if not device is Dictionary or (str(device.get("type","")) not in LOGISTICS.PROCESSORS and device.get("type") not in INDUSTRY.MANUAL_STATIONS) or not device.has("processing"):continue
		if device.has("job") or device.get("auto_enabled",false) or not device.processing is Dictionary:continue
		var advanced:Dictionary=COOKING_QUEUE.advance(device.processing,processing_recipes(str(device.type),true),now)
		if not advanced.ok or not advanced.changed:continue
		device.processing=advanced.state
		var used_here:Dictionary=_undo_used.get(_region,{})
		used_here[k]=true
		_undo_used[_region]=used_here
		changed=true
	return changed

## INDUSTRY.PROCESS entries whose station is `station` (fresh copy).
static func processing_recipes(station: String, include_retired:=false) -> Dictionary:
	if station=="seed_maker":return SEED_MAKER.recipes(CROPS,include_retired)
	var out:={}
	for kind in INDUSTRY.PROCESS:
		var recipe:Dictionary=INDUSTRY.PROCESS[kind]
		if INDUSTRY.uses_station(kind,station):out[kind]=recipe.duplicate(true)
	return out

## Recipe table a given stove object type cooks from: the early 小石灶 keeps its exact old numbers
## (minus the C12-only dishes); the C12 公共廚房灶台 uses the canonical D01-D16 numbers.
static func stove_recipes(kind: String) -> Dictionary:
	return KITCHEN_STOVE.recipes_for(kind,RECIPES)

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
static func has_recipe(person:Dictionary,id:String) -> bool:
	return RECIPES.has(id) and (id!=RESIDENT_GOALS.SEAFOOD_RICE or RESIDENT_GOALS.done(person,"achao").has(3))

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
		# Station table: the C12 stove cooks the canonical D01-D16 numbers, the early stove the old ones.
		var table:Dictionary=stove_recipes(str(stove.get("type","")))
		if not table.has(extra) or not has_recipe(player,extra):return fail("還沒有這份食譜")
		# D16 / D11 / D15: the C12 stove cooks 糰糰火鍋 after the festival preparation, 茶香布丁 / 花園餅乾 after the
		# player's own 熟悉 event (new jobs only; queued ones are untouched). D13 stays in has_recipe above.
		if stove_dish_locked(player,str(stove.get("type","")),extra):return fail(str(KITCHEN_STOVE.gate(str(stove.get("type","")),extra).message))
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
		var recipe:Dictionary=table[extra]
		for item in recipe.ingredients:
			if int(inv.get(item,0))<int(recipe.ingredients[item]):return fail("缺少"+str(NAMES.get(item,item))+" %d"%int(recipe.ingredients[item]))
		var id:=_queue_new_id(base)
		if id=="":return fail(COOKING_MSG_CORRUPT)
		var queued:Dictionary=COOKING_QUEUE.enqueue(base,table,now,token,extra,id,inv)
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

static func master_bench_anchor(objects:Dictionary,tile:Vector2i) -> Vector2i:
	var piece:Dictionary=objects.get(key(tile),{})
	return tile-master_bench_offset(piece) if piece.get("type") in RESIDENT_GOALS.DOUBLE_BENCHES and piece.get("bench_end",false) else tile

static func master_bench_offset(piece:Dictionary) -> Vector2i:
	return Vector2i.DOWN if piece.get("bench_vertical",false) else Vector2i.RIGHT

static func station_anchor(objects:Dictionary,tile:Vector2i) -> Vector2i:
	var obj:Dictionary=objects.get(key(tile),{})
	var part:=INDUSTRY.square_part(obj)
	var cells:=INDUSTRY.station_cells(str(obj.get("type","")),INDUSTRY.is_vertical(obj))
	return tile-cells[part] if part in range(cells.size()) else tile

func _write_station_parts(anchor:Vector2i,obj:Dictionary,layer:="objects") -> void:
	var field:=INDUSTRY.square_part_field(obj.type)
	var cells:=INDUSTRY.station_cells(obj.type,INDUSTRY.is_vertical(obj))
	for part in range(1,cells.size()):
		var child:={"type":obj.type,"owner":obj.owner,"items":{},field:part}
		if INDUSTRY.is_vertical(obj):child[INDUSTRY.vertical_field(obj.type)]=true
		# C13: every mill cell repeats the facing; none of them copies the anchor's buffers/queue/job.
		if INDUSTRY.is_new_mill(obj):child[INDUSTRY.MILL_FACING]=INDUSTRY.mill_facing(obj)
		if obj.type==INDUSTRY.BEACH_CHAIR and obj.get("beach_chair_folded",false):child.beach_chair_folded=true
		if INDUSTRY.is_folded_screen(obj):child[INDUSTRY.RIVERSIDE_FOLDED_FIELD]=true
		state[layer][key(anchor+cells[part])]=child

func _seat_occupied(anchor:Vector2i, side:=-1)->bool:
	var seat_key:=key(anchor)
	for other:String in regional_tokens():
		var seat:Dictionary=state.players[other].get(RESIDENT_GOALS.MASTER_BENCH_SEAT,{})
		if seat.get("cell")==seat_key and (side<0 or int(seat.side)==side):return true
	return false

func _beach_chair_action(token:String,player:Dictionary,p:Vector2i,action:String,extra:String)->Dictionary:
	var anchor:=station_anchor(state.objects,p)
	var k:=key(anchor)
	var obj:Dictionary=state.objects.get(k,{})
	if not extra.is_empty() or obj.get("type")!=INDUSTRY.BEACH_CHAIR:return fail("請靠近折疊沙灘椅。")
	var seat_field:=RESIDENT_GOALS.MASTER_BENCH_SEAT
	var folded:bool=obj.get("beach_chair_folded",false)
	if action==INDUSTRY.BEACH_SIT:
		if player.get(seat_field,{}).get("cell")==k:
			player.erase(seat_field)
			return ok("你從沙灘椅起身。")
		if folded:return fail("沙灘椅收起來了，請先展開。")
		if player.has(seat_field) or _seat_occupied(anchor):return fail(INDUSTRY.BEACH_BUSY)
		_master_bench_clear(anchor)
		return _claim_seat(token,player,{"cell":k,"side":0},"你坐下來吹吹風。")
	if obj.owner!=token:return fail("只有椅子的主人能收起或展開。")
	if _seat_occupied(anchor):return fail(INDUSTRY.BEACH_BUSY)
	if folded:
		var space:=_footprint_space(token,anchor,INDUSTRY.station_cells(obj.type,INDUSTRY.is_vertical(obj)),anchor)
		if not space.ok:return space
		obj.erase("beach_chair_folded")
	else:obj.beach_chair_folded=true
	_master_bench_clear(anchor)
	_write_station_parts(anchor,obj)
	return ok("沙灘椅展開了。" if folded else "沙灘椅收起來了。")

## T10 竹編躺椅: toggles the existing resident seat pose (cell = anchor, side 0). Either tile works.
## No energy, no clock change, no bed or free item: it only stores the pose; moving also stands up.
func _bamboo_lounger_rest(token:String,player:Dictionary,p:Vector2i,extra:String)->Dictionary:
	var anchor:=station_anchor(state.objects,p)
	var k:=key(anchor)
	if not extra.is_empty() or state.objects.get(k,{}).get("type")!=INDUSTRY.BAMBOO_LOUNGER:return fail("請靠近竹編躺椅。")
	var seat_field:=RESIDENT_GOALS.MASTER_BENCH_SEAT
	if player.get(seat_field,{}).get("cell")==k:
		player.erase(seat_field)
		return ok("你從竹編躺椅起身。")
	if player.has(seat_field) or _seat_occupied(anchor):return fail(INDUSTRY.LOUNGER_BUSY)
	_master_bench_clear(anchor)
	return _claim_seat(token,player,{"cell":k,"side":0},"你在竹編躺椅上躺下休息。")

## T11 茶屋點心架: moves real cooked food between the actor's inventory and ONE tier of the shelf.
## extra = "<tier>:<item>:<count>". The server re-checks reach, target, access policy, food
## eligibility, counts, tier capacity and the inventory ceiling; the client only previews.
func _tea_snack_shelf_action(token:String,player:Dictionary,p:Vector2i,dist:float,action:String,extra:String)->Dictionary:
	var shelf:Dictionary=state.objects.get(key(p),{})
	if dist>INDUSTRY.SNACK_REACH or shelf.get("type")!=INDUSTRY.TEA_SNACK_SHELF:return fail("請靠近茶屋點心架。")
	var permission:=PLOT_PERMISSIONS.can_take(token,shelf)
	if not permission.ok:return fail(permission.message)
	var request:=INDUSTRY.parse_snack_request(extra)
	if not request.ok:return fail(str(request.message))
	var item:String=request.item
	var count:int=request.count
	var tier_index:int=request.tier
	if not NAMES.has(item) or not INDUSTRY.snack_food(item,RECIPES):return fail("點心架只能放可以吃的料理。")
	if not shelf.get(INDUSTRY.SNACK_FIELD) is Array:shelf[INDUSTRY.SNACK_FIELD]=INDUSTRY.fresh_snack_tiers()
	var tiers:Array=shelf[INDUSTRY.SNACK_FIELD]
	if tiers.size()!=INDUSTRY.SNACK_TIER_NAMES.size() or not tiers[tier_index] is Dictionary:return fail("點心架的資料有誤，這次沒有變更。")
	var tier:Dictionary=tiers[tier_index]
	var tier_name:String=INDUSTRY.SNACK_TIER_NAMES[tier_index]
	var inv:Dictionary=player.inventory
	var shelved:int=int(tier.get(item,0))
	if action==INDUSTRY.SNACK_PUT:
		if int(inv.get(item,0))<count:return fail("背包裡的%s不夠。"%NAMES[item])
		if shelved==0 and tier.size()>=INDUSTRY.SNACK_TIER_KINDS:return fail("%s已放了 %d 種點心，先取出一種。"%[tier_name,INDUSTRY.SNACK_TIER_KINDS])
		if shelved+count>INDUSTRY.SNACK_TIER_LIMIT:return fail("%s的%s最多放 %d 份。"%[tier_name,NAMES[item],INDUSTRY.SNACK_TIER_LIMIT])
		give(inv,item,-count)
		tier[item]=shelved+count
		return ok("已把 %d 份%s放上%s。"%[count,NAMES[item],tier_name])
	if shelved<count:return fail("%s裡的%s不夠。"%[tier_name,NAMES[item]])
	if not ITEM_CATALOG.can_hold(item,int(inv.get(item,0))+count):return fail("背包放不下這些點心，仍留在點心架。")
	give(inv,item,count)
	if shelved==count:tier.erase(item)
	else:tier[item]=shelved-count
	return ok("已從%s取出 %d 份%s。"%[tier_name,count,NAMES[item]])

## True when any active player of this region has a foot corner inside one of `anchor`'s screen
## tiles. Stricter than _footprint_space's centre-distance test, which misses a body that only
## clips a tile corner; a solid screen dropped there would leave that body stuck in it.
func _riverside_screen_occupied(anchor:Vector2i,vertical:bool)->bool:
	var tiles:Array=[]
	for offset:Vector2i in INDUSTRY.station_cells(INDUSTRY.RIVERSIDE_SCREEN,vertical):tiles.append(anchor+offset)
	for other:String in regional_tokens():
		var person:Dictionary=state.players[other]
		if INDUSTRY.foot_box_hits(Vector2(float(person.x),float(person.y)),tiles):return true
	return false

func _riverside_screen_action(token:String,p:Vector2i,extra:String)->Dictionary:
	var anchor:=station_anchor(state.objects,p)
	var obj:Dictionary=state.objects.get(key(anchor),{})
	if not extra.is_empty() or obj.get("type")!=INDUSTRY.RIVERSIDE_SCREEN or INDUSTRY.square_part(obj)!=0:return fail("請靠近河岸屏風。")
	if obj.owner!=token:return fail(INDUSTRY.RIVERSIDE_NOT_OWNER)
	var vertical:=INDUSTRY.is_vertical(obj)
	if INDUSTRY.is_folded_screen(obj):
		var space:=_footprint_space(token,anchor,INDUSTRY.station_cells(obj.type,vertical),anchor,false)
		if not space.ok:return space
		if _riverside_screen_occupied(anchor,vertical):return fail(INDUSTRY.RIVERSIDE_OCCUPIED)
		obj.erase(INDUSTRY.RIVERSIDE_FOLDED_FIELD)
	else:
		obj[INDUSTRY.RIVERSIDE_FOLDED_FIELD]=true
	_write_station_parts(anchor,obj)
	return ok("河岸屏風展開了。" if not INDUSTRY.is_folded_screen(obj) else "河岸屏風收起來了，兩格都能通行。")

func _shell_table_action(token:String,player:Dictionary,tile:Vector2i,distance:float,action:String,item:String)->Dictionary:
	var tile_key:=key(tile)
	var table:Dictionary=state.objects.get(tile_key,{})
	if table.get("type")==INDUSTRY.ROUNDED_TABLE:
		return _rounded_table_action(token,player,station_anchor(state.objects,tile),action,item)
	var round_table:bool=table.get("type")==INDUSTRY.SHELL_TABLE
	if action==INDUSTRY.ROUNDED_EAT:return fail("請靠近圓角木桌享用餐點。")
	if not round_table and (table.get("type")!="table" or action==INDUSTRY.SHELL_SIT):return fail("請靠近可以展示的桌子。")
	var seat_field:=RESIDENT_GOALS.MASTER_BENCH_SEAT
	if action==INDUSTRY.SHELL_SIT and player.get(seat_field,{}).get("cell")==tile_key:
		player.erase(seat_field)
		return ok("你從圓桌旁起身。")
	if distance>3.2:return fail("請靠近桌子。")
	if action==INDUSTRY.SHELL_SIT:
		if player.has(seat_field) or item not in ["0","1"]:return fail("請選擇左側或右側的座位。")
		var side:=int(item)
		if _seat_occupied(tile,side):return fail("這個座位有人了。")
		_master_bench_clear(tile,side)
		return _claim_seat(token,player,{"cell":tile_key,"side":side},"你坐在圓桌旁吹吹海風。")
	if table.owner!=token:return fail("只有桌子的主人能更換展示品。")
	var bag:Dictionary=player.inventory
	if action==INDUSTRY.TABLE_VASE_SWAP:
		var shown:String=table.items.keys()[0] if table.items.size()==1 else ""
		return _swap_table_vase(table.items,bag,shown,item)
	if not ITEM_CATALOG.is_known(item):return fail("請選擇可以展示的物品。")
	if not round_table and item not in INDUSTRY.WOOD_TABLE_DISPLAY:return fail("木桌可以展示花瓶、玻璃貝殼瓶或小陶茶具。")
	if action==INDUSTRY.SHELL_PUT:
		if not table.items.is_empty():return fail("桌面已有展示品，請先取回。")
		if int(bag.get(item,0))<1:return fail("背包裡沒有這個物品。")
		give(bag,item,-1)
		table.items[item]=1
		return ok("展示了%s。"%NAMES.get(item,item))
	if not table.items.has(item):return fail("展示品已經換過了。")
	if not ITEM_CATALOG.can_hold(item,int(bag.get(item,0))+1):return fail("背包放不下，展示品仍留在桌上。")
	table.items.erase(item)
	give(bag,item,1)
	return ok("取回了%s。"%NAMES.get(item,item))

func _swap_table_vase(items:Dictionary,bag:Dictionary,shown:String,flower:String)->Dictionary:
	var previous:String=INDUSTRY.TABLE_VASE_BLOOMS.get(shown,"")
	var replacement:Variant=INDUSTRY.TABLE_VASE_BLOOMS.find_key(flower)
	if previous.is_empty() or replacement==null or int(items.get(shown,0))<1:return fail("請把花瓶擺上桌，再選一枝新花。")
	if previous==flower:return fail("花瓶已經插著這種花了。")
	if int(bag.get(flower,0))<1:return fail("背包裡沒有這種花。")
	if not ITEM_CATALOG.can_hold(previous,int(bag.get(previous,0))+1):return fail("背包放不下取回的花。")
	give(bag,flower,-1)
	give(bag,previous,1)
	_decrement_table_item(items,shown)
	give(items,replacement,1)
	return ok("換上%s，原來的%s已放回背包。"%[NAMES[flower],NAMES[previous]])

func _rounded_table_action(token:String,player:Dictionary,anchor:Vector2i,action:String,item:String)->Dictionary:
	var table:Dictionary=state.objects[key(anchor)]
	var position:=Vector2(player.x,player.y)
	var center:=Vector2(anchor)+Vector2(0.5,0.5)
	var side:=Vector2.DOWN if INDUSTRY.is_vertical(table) else Vector2.RIGHT
	if minf(position.distance_to(center),position.distance_to(center+side))>3.2:return fail("請靠近圓角木桌。")
	if action==INDUSTRY.SHELL_SIT:return fail("請到桌旁的座椅入座。")
	if action!=INDUSTRY.ROUNDED_EAT and table.owner!=token:return fail("只有屋主能擺放或收回桌上的東西。")
	var items:Dictionary=table.items
	var bag:Dictionary=player.inventory
	if action==INDUSTRY.TABLE_VASE_SWAP:
		var parts:=item.split(":")
		if parts.size()!=2:return fail("請選擇花瓶與新花。")
		return _swap_table_vase(items,bag,parts[0],parts[1])
	if not INDUSTRY.rounded_table_item(item,RECIPES):return fail("請選擇桌面小物或共享餐點。")
	var title:String=NAMES[item]
	if action==INDUSTRY.SHELL_PUT:
		if INDUSTRY.rounded_table_count(items)>=INDUSTRY.ROUNDED_CAPACITY:return fail("兩個位置都放滿了，請先空出一格。")
		if int(bag.get(item,0))<1:return fail("背包裡沒有這個物品。")
		give(bag,item,-1)
		give(items,item,1)
		return ok("擺上了%s。"%title)
	if int(items.get(item,0))<1:return fail("桌上已經沒有這個物品了。")
	if action==INDUSTRY.ROUNDED_EAT:
		if not INDUSTRY.shareable_meal(item,RECIPES):return fail("這是桌面擺飾，請選料理。")
		_decrement_table_item(items,item)
		MEAL_BUFF.restore(player,INDUSTRY.MUSHROOM_MEAL_ENERGY)
		return ok("享用了一份%s。"%title)
	if not ITEM_CATALOG.can_hold(item,int(bag.get(item,0))+1):return fail("背包放不下，展示品仍留在桌上。")
	_decrement_table_item(items,item)
	give(bag,item,1)
	return ok("取回了%s。"%title)

## The tea table keeps the set in its own flag: meal stock, the four-portion cap and the
## eat/take-meal paths never see it, and it adds no energy or sale value.
func _tea_table_set(player:Dictionary,table:Dictionary,put:bool)->Dictionary:
	var bag:Dictionary=player.inventory
	var title:String=NAMES[INDUSTRY.TEA_SET]
	if put:
		if table.get(INDUSTRY.TEA_SET_FIELD,false):return fail("茶桌上已經擺著小陶茶具了。")
		if int(bag.get(INDUSTRY.TEA_SET,0))<1:return fail("背包裡沒有小陶茶具。")
		give(bag,INDUSTRY.TEA_SET,-1)
		table[INDUSTRY.TEA_SET_FIELD]=true
		return ok("擺上了%s。"%title)
	if not table.get(INDUSTRY.TEA_SET_FIELD,false):return fail("桌上沒有小陶茶具。")
	if not ITEM_CATALOG.can_hold(INDUSTRY.TEA_SET,int(bag.get(INDUSTRY.TEA_SET,0))+1):return fail("背包放不下，茶具仍留在桌上。")
	table.erase(INDUSTRY.TEA_SET_FIELD)
	give(bag,INDUSTRY.TEA_SET,1)
	return ok("取回了%s。"%title)

## Host-side authority for the pouring emotes: some table with a placed tea set must be within
## reach of the sender in the sender's own region. Owner is irrelevant, so visitors can pour.
## Pure read; never touches inventory, coins or any table.
func tea_set_nearby(token:String)->bool:
	var player:Dictionary=state.players.get(token,{})
	if player.is_empty():return false
	var layers:Dictionary=_layers_of(player_region(token))
	var objects:Dictionary=layers.get("objects",{})
	var at:=Vector2(float(player.x),float(player.y))
	var center:=Vector2i(at.floor())
	var reach:=ceili(INDUSTRY.TEA_SET_REACH)
	for y in range(center.y-reach,center.y+reach+1):
		for x in range(center.x-reach,center.x+reach+1):
			var tile:=Vector2i(x,y)
			var piece:Dictionary=objects.get(key(tile),{})
			if piece.get("type","") not in ["table",INDUSTRY.ROUNDED_TABLE,INDUSTRY.SHELL_TABLE,INDUSTRY.BAMBOO_TEA_TABLE]:continue
			if at.distance_to(Vector2(tile)+Vector2(0.5,0.5))>INDUSTRY.TEA_SET_REACH:continue
			var table:Dictionary=objects.get(key(station_anchor(objects,tile)),{})
			if INDUSTRY.has_tea_set(table):return true
	return false

static func _decrement_table_item(items:Dictionary,item:String)->void:
	if int(items[item])==1:items.erase(item)
	else:give(items,item,-1)

func _hollow_bed_rest(token:String,player:Dictionary,tile:Vector2i,extra:String)->Dictionary:
	var anchor:=station_anchor(state.objects,tile)
	var tile_key:=key(anchor)
	if state.objects.get(tile_key,{}).get("type")!=INDUSTRY.HOLLOW_BED or not extra.is_empty():
		return fail("請靠近樹洞小床。")
	var seat_field:=RESIDENT_GOALS.MASTER_BENCH_SEAT
	if player.get(seat_field,{}).get("cell")==tile_key:
		player.erase(seat_field)
		return ok("你從樹洞小床起身。")
	if player.has(seat_field):return fail("請先起身再躺下。")
	if not _near_station(player,anchor,INDUSTRY.SQUARE_CELLS):return fail("請靠近樹洞小床。")
	if _seat_occupied(anchor):return fail(INDUSTRY.HOLLOW_BUSY)
	_master_bench_clear(anchor)
	MEAL_BUFF.refill(player)
	return _claim_seat(token,player,{"cell":tile_key,"side":0},"在樹洞裡休息了一下，體力已恢復。")

func _cedar_bed_action(token:String,player:Dictionary,tile:Vector2i,distance:float,choice:String)->Dictionary:
	if _region!=REGIONS.HOME or distance>3.2 or state.objects.get(key(tile),{}).get("type")!=INDUSTRY.CEDAR_BED:
		return fail("請靠近家園的原木小床。")
	var anchor:=key(station_anchor(state.objects,tile))
	if state.objects[anchor].owner!=token:return fail("只有床的主人能在這裡休息或設定休息處。")
	match choice:
		"mark":
			player[INDUSTRY.HOME_REST_FIELD]=anchor
			return ok("已設為你的個人休息處。")
		"rest":
			MEAL_BUFF.refill(player)
			return ok("休息了一會兒，探索體力已恢復。")
	return fail("請選擇休息或設定個人休息處。")

func _near_station(player:Dictionary,anchor:Vector2i,offsets:Array)->bool:
	var position:=Vector2(player.x,player.y)
	for offset:Vector2i in offsets:
		if position.distance_to(Vector2(anchor+offset)+Vector2(0.5,0.5))<=3.2:return true
	return false

func _four_seat_table_action(token:String,player:Dictionary,tile:Vector2i,action:String,extra:String)->Dictionary:
	var anchor:=station_anchor(state.objects,tile)
	var tile_key:=key(anchor)
	var table:Dictionary=state.objects.get(tile_key,{})
	var kind:String=table.get("type","")
	if kind not in INDUSTRY.FOUR_SEAT_TABLES:return fail("請靠近傘帽圓桌或低腳竹茶桌。")
	var table_name:String=BUILD[kind].name
	var nearby:=_near_station(player,anchor,INDUSTRY.station_cells(kind,INDUSTRY.is_vertical(table)))
	var seat_field:=RESIDENT_GOALS.MASTER_BENCH_SEAT
	var sitting:bool=player.get(seat_field,{}).get("cell")==tile_key
	if action==INDUSTRY.MUSHROOM_SIT:
		if extra=="leave" and sitting:
			player.erase(seat_field)
			return ok("你從"+table_name+"起身。")
		if player.has(seat_field):return fail("請先起身再選座位。")
		if not nearby:return fail("請靠近"+table_name+"。")
		if extra not in ["0","1","2","3"]:return fail("請選擇一個座位。")
		var side:=int(extra)
		if _seat_occupied(anchor,side):return fail("這個座位有人了。")
		_master_bench_clear(anchor,side)
		return _claim_seat(token,player,{"cell":tile_key,"side":side},"你在"+table_name+"旁坐下。")
	if not sitting and not nearby:return fail("請靠近"+table_name+"。")
	if action==INDUSTRY.MUSHROOM_EAT and not sitting:return fail("先入座，就能享用桌上的餐點。")
	if action!=INDUSTRY.MUSHROOM_EAT and table.owner!=token:return fail("只有桌子的主人能上菜或收回餐點。")
	if extra==INDUSTRY.TEA_SET and action!=INDUSTRY.MUSHROOM_EAT and kind==INDUSTRY.BAMBOO_TEA_TABLE:
		return _tea_table_set(player,table,action==INDUSTRY.MUSHROOM_SERVE)
	if not INDUSTRY.four_seat_meal(kind,extra,RECIPES):
		return fail("茶桌上可以放茶飲、布丁、餅乾或吐司。" if kind==INDUSTRY.BAMBOO_TEA_TABLE else "請選擇可以共餐的料理。")
	var bag:Dictionary=player.inventory
	var available:=int(table.items.get(extra,0))
	var title:String=NAMES[extra]
	if action==INDUSTRY.MUSHROOM_SERVE:
		var total:=0
		for amount in table.items.values():total+=int(amount)
		if total>=INDUSTRY.MUSHROOM_TABLE_CAPACITY:return fail("桌面擺滿了四份餐點。")
		if int(bag.get(extra,0))<1:return fail("背包沒有這道料理。")
		give(bag,extra,-1)
		table.items[extra]=available+1
		return ok(title+"上桌了。")
	if available<=0:return fail("桌上已經沒有這道料理了。")
	if action==INDUSTRY.MUSHROOM_TAKE and not ITEM_CATALOG.can_hold(extra,int(bag.get(extra,0))+1):
		return fail("背包放不下這道料理。")
	if available==1:table.items.erase(extra)
	else:table.items[extra]=available-1
	if action==INDUSTRY.MUSHROOM_TAKE:
		give(bag,extra,1)
		return ok("收回了一份"+title+"。")
	MEAL_BUFF.restore(player,INDUSTRY.MUSHROOM_MEAL_ENERGY)
	return ok("享用了一份"+title+"。")

## T12 不完美的茶亭: static layout facts the shelter may never cover (shared with the client's placement
## ghost). Returns "" or the reason. Region exits/spawns and travel stops, resident and walk-up
## resident spots, and (home) the village footpaths and every fixed interaction cell.
static func essential_cell_reason(snapshot:Dictionary,region:String,tile:Vector2i) -> String:
	var reason:String=PAVILION.ESSENTIAL_MESSAGE
	if tile==REGIONS.exit_cell(region) or tile==Vector2i(REGIONS.spawn(region)):return reason
	if not TRANSIT.point_at(region,tile).is_empty():return reason
	for resident:String in Village.ids_for_region(region):
		if resident!="xiaoli" and Village.resident_cell(snapshot,resident)==tile:return reason
	for walker:String in RESIDENT_BOND.RESIDENTS:
		var spot:Array=bond_place(snapshot,walker)
		if str(spot[0])==region and Vector2i(spot[1])==tile:return reason
	if region!=REGIONS.HOME:return ""
	if VILLAGE_LAYOUT.path_at(Vector2(tile)+Vector2(0.5,0.5)):return reason
	var fixed:Array[Vector2i]=[Vector2i(40,29),Vector2i(43,29),Vector2i(45,33),Vector2i(54,25),COPPER_CELL,SEAWEED_CELL,
		Vector2i(SPAWN),Vector2i(WANGAN_COAST.FERRY_LANDING),Vector2i(Festival.TREE_CELL),Vector2i(Hedgehog.site(snapshot)),
		Vector2i(Squirrel.SITE),Vector2i(Seal.SITE),Vector2i(Deer.site(snapshot)),Vector2i(Dog.SITE),Vector2i(Cat.site(snapshot)),
		Vector2i(WANGAN_MEMORY.SITE),Vector2i(WANGAN_MEMORY.COURT_SIGN),Vector2i(WANGAN_MEMORY.WEIR_SITE),Vector2i(WANGAN_MEMORY.WEIR_LOOKOUT),
		Vector2i(WANGAN_COAST.SHELL_CELL),Vector2i(WANGAN_COAST.STAR_SAND),Vector2i(WANGAN_COAST.DOCK_ORDERS),Vector2i(WANGAN_COAST.STAR_REPAIR),Vector2i(WANGAN_COAST.SALT_PARCEL),
		Vector2i(RESIDENT_GOALS.ARU_PARK_VIEW),Vector2i(SHIPPING.cell_for(snapshot)),Vector2i(COMMUNITY.table_cell(snapshot)),
		Vector2i(MARKET.active_cell(snapshot)),Vector2i(FISH_MEET.SIGN),PUBLIC_TILLER.site(snapshot)]
	for animal_id:String in LIVESTOCK.ANIMALS:
		var animal:Dictionary=LIVESTOCK.ANIMALS[animal_id]
		var animal_cell:Vector2i=animal.cell
		fixed.append(animal_cell)
	return reason if tile in fixed else ""

## Authoritative site check for the 3×3 shelter: every cell must clear the live map's protected
## and statically blocked cells (not objects/water/resources — _footprint_space words those)
## and the static layout facts above. Used by build, blueprint simulation and moving.
func pavilion_site_problem(anchor:Vector2i) -> String:
	for offset:Vector2i in INDUSTRY.station_cells(INDUSTRY.IMPERFECT_TEA_PAVILION):
		var spot:=anchor+offset
		if protected(spot):return PAVILION.ESSENTIAL_MESSAGE
		if blocked(spot) and not water(spot) and resource(spot)=="" and not state.objects.has(key(spot)):return PAVILION.ESSENTIAL_MESSAGE
		var reason:=essential_cell_reason(state,_region,spot)
		if not reason.is_empty():return reason
	return ""

func _footprint_space(builder:String,anchor:Vector2i,offsets:Array,ignore:Vector2i=Vector2i(-1000,-1000),check_occupants:=true) -> Dictionary:
	for offset:Vector2i in offsets:
		var spot:=anchor+offset
		if not allows_public_build(builder,spot):return fail(PUBLIC_BUILD_DENIED)
		var floor_permission:=PLOT_PERMISSIONS.placement_floor(self,builder,spot)
		if not floor_permission.ok:return fail(floor_permission.message)
		var cell_key:=key(spot)
		if water(spot) or protected(spot) or state.crops.has(cell_key) or resource(spot)!="":
			return fail("整件家具需要落在可施工的空地。")
		if state.objects.has(cell_key) and spot-ignore not in offsets:
			return fail("整件家具的占地都需要留空。")
		if check_occupants:
			for token:String in regional_tokens():
				var person:Dictionary=state.players[token]
				if Vector2(person.x,person.y).distance_to(Vector2(spot)+Vector2(0.5,0.5))<0.8:
					return fail("占地範圍有人，請先讓開。")
	return ok("")

## C13: true when the cell in front of a mill entrance can be walked on. While a mill moves, its own old
## footprint (`moving_from`) is about to be erased, so those cells count as open.
func _mill_front_open(front:Vector2i,moving_from:=Vector2i(-1000,-1000)) -> bool:
	if moving_from!=Vector2i(-1000,-1000) and front-moving_from in INDUSTRY.mill_cells():return true
	return is_land(front) and not blocked(front)

## C13: "" when a new mill at `anchor` facing `facing` has a walkable cell in front of its entrance and nobody
## stands inside its eight solid cells (the entrance cell itself is walkable, so people there never block).
func _mill_site_problem(anchor:Vector2i,facing:int,moving_from:=Vector2i(-1000,-1000)) -> String:
	if not _mill_front_open(anchor+INDUSTRY.mill_front_offset(facing),moving_from):return INDUSTRY.MILL_ENTRANCE_BLOCKED
	if _mill_entrance_walled(state.edges,anchor,facing):return INDUSTRY.MILL_ENTRANCE_BLOCKED
	var entrance:=INDUSTRY.mill_entrance_offset(facing)
	var solid:Array[Vector2i]=[]
	for offset:Vector2i in INDUSTRY.mill_cells():
		if offset!=entrance:solid.append(anchor+offset)
	for person_token:String in regional_tokens():
		var person:Dictionary=state.players[person_token]
		if INDUSTRY.foot_box_hits(Vector2(float(person.x),float(person.y)),solid):return "占地範圍有人，請先讓開。"
	return ""

static func _mill_entrance_walled(edges:Dictionary,anchor:Vector2i,facing:int)->bool:
	if edges.is_empty():return false
	var entrance:=anchor+INDUSTRY.mill_entrance_offset(facing)
	var front:=anchor+INDUSTRY.mill_front_offset(facing)
	var side:=EDGE_GRID.DIRS.find(front-entrance)
	var row:Dictionary=edges.get(EDGE_GRID.key(entrance,side,SIZE),{})
	return not row.is_empty() and (row.get("type")!="edge_door" or not row.get("open",false))

## C13: a solid kind (or a closed door) may never cover the open cell in front of an existing mill
## entrance, otherwise the entrance would be walled in. `open_offset` is a footprint cell that stays
## walkable (the entrance of a mill being placed); `ignore` is the anchor of a mill being moved.
func _mill_front_claim_problem(kind:String,anchor:Vector2i,has_footprint:bool,vertical:=false,ignore:=Vector2i(-1000,-1000),open_offset:=Vector2i(-1000,-1000)) -> String:
	if kind not in UNDO_SOLID and kind!="door":return ""
	var offsets:Array=INDUSTRY.station_cells(kind,vertical) if has_footprint else [Vector2i.ZERO]
	for offset:Vector2i in offsets:
		if offset!=open_offset and INDUSTRY.is_mill_front(state.objects,anchor+offset,ignore):return INDUSTRY.MILL_FRONT_BLOCKED
	return ""

func _master_bench_end(anchor:Vector2i,obj:Dictionary) -> void:
	var end:={"type":obj.type,"owner":obj.owner,"items":{},"bench_end":true}
	if obj.get("bench_vertical",false):end.bench_vertical=true
	state.objects[key(anchor+master_bench_offset(obj))]=end

func _master_bench_clear(anchor:Vector2i, side:=-1) -> void:
	var seat_key:=key(anchor)
	for person:Dictionary in state.players.values():
		var seat:Dictionary=person.get(RESIDENT_GOALS.MASTER_BENCH_SEAT,{})
		if person.get("region",REGIONS.HOME)==_region and seat.get("cell")==seat_key and (side<0 or int(seat.side)==side):
			person.erase(RESIDENT_GOALS.MASTER_BENCH_SEAT)

func _master_bench_sit(token:String,player:Dictionary,tile:Vector2i) -> Dictionary:
	var goals:=RESIDENT_GOALS
	var anchor:=master_bench_anchor(state.objects,tile)
	var furniture:Dictionary=state.objects.get(key(anchor),{})
	var kind=furniture.get("type")
	var public_bench:=_region==REGIONS.HOME and goals.aru_public_bench(furniture)
	var titles:={goals.GARDEN_CHAIR:"庭園椅",INDUSTRY.MUSHROOM_STOOL:"小菇矮凳",INDUSTRY.WOOD_CHAIR:"矮背木椅",INDUSTRY.INDIGO_CUSHION:"靛藍坐墊",goals.COTTON_SOFA:"棉布雙人沙發",goals.BAMBOO_BENCH:"雙人竹長椅"}
	if (not public_bench and kind not in titles and kind not in goals.DOUBLE_BENCHES) or (kind==goals.MASTER_BENCH and _region!=REGIONS.HOME):return fail("請靠近可坐的椅子。")
	var title:String=titles.get(kind,"長椅")
	if player.has(goals.MASTER_BENCH_SEAT):
		if kind in goals.INDEPENDENT_TWO_SEATS and player[goals.MASTER_BENCH_SEAT].cell!=key(anchor):return fail("請先從原本的座位起身。")
		player.erase(goals.MASTER_BENCH_SEAT)
		return ok("你從%s上起身。"%title)
	if public_bench:
		for side in goals.ARU_PARK_SEAT_X.size():
			var feet:=Vector2(anchor)+Vector2(goals.ARU_PARK_SEAT_X[side],1.45)
			if _seat_occupied(anchor,side) or not can_stand(feet) or not can_enter_room_floor(token,feet):continue
			var result:=_claim_seat(token,player,{"cell":key(anchor),"side":side},"你在渡口的公共長椅坐了一會兒。")
			if result.ok:
				player.x=feet.x
				player.y=feet.y
			return result
		return fail("公共長椅沒有空位了。")
	var seat:={"cell":key(anchor),"side":absi(tile.x-anchor.x)+absi(tile.y-anchor.y)}
	return _claim_seat(token,player,seat,"你在%s上坐了一會兒。"%title)

func _claim_seat(token:String,player:Dictionary,seat:Dictionary,message:String) -> Dictionary:
	var field:=RESIDENT_GOALS.MASTER_BENCH_SEAT
	for other:String in regional_tokens():
		if other!=token and state.players[other].get(field)==seat:return fail("這個座位有人了。")
	var furniture:Dictionary=state.objects.get(seat.cell,{})
	var seat_kind:String=furniture.get("type","")
	if seat_kind in RESIDENT_GOALS.INDEPENDENT_TWO_SEATS or RESIDENT_GOALS.aru_public_bench(furniture):
		_master_bench_clear(cell(seat.cell),int(seat.side))
	elif seat_kind in [RESIDENT_GOALS.GARDEN_CHAIR,INDUSTRY.MUSHROOM_STOOL,INDUSTRY.WOOD_CHAIR,INDUSTRY.INDIGO_CUSHION]:
		# After a disconnect or restart, an inactive character may still have a saved pose.
		_master_bench_clear(cell(seat.cell))
	player.erase("fishing")
	player[field]=seat
	return ok(message)

func _sit_at_inn(person:Dictionary,choice:String) -> void:
	var seat:Vector2i=REGIONS.Springs.REST_SEATS[choice]
	person[REGIONS.Springs.REST_SEAT_KEY]=choice
	person.x=seat.x+0.55
	person.y=seat.y+0.66

## Another connected player really sitting at this seat key. Entries whose saved pose is stale
## (wrong region, inactive, or no longer at the spot) never count.
func _rest_seat_taken(token:String,seat_key:String) -> bool:
	var spot:Vector2=REGIONS.Springs.rest_spot(seat_key)
	var seated:={}
	for other:String in active_tokens:
		if other==token:continue
		var visitor:Dictionary=state.players.get(other,{})
		if visitor.is_empty() or str(visitor.get("region",REGIONS.HOME))!=REGIONS.Springs.REGION:continue
		if Vector2(float(visitor.get("x",-1000)),float(visitor.get("y",-1000))).distance_to(spot)>0.9:continue
		seated[other]=visitor
	return REGIONS.Springs.rest_occupied(seated,seat_key)

## Called when a peer leaves: only this person's story seats are released.
func release_story_seats(token:String) -> void:
	var person:Dictionary=state.players.get(token,{})
	if person.is_empty():return
	person.erase(REGIONS.Springs.REST_SEAT_KEY)
	person.erase(TEA_HOUSE_INTERIOR.SEAT_KEY)
	person.erase(RESIDENT_GOALS.DIANDIAN_SEAT_KEY)
	person.erase(RESIDENT_GOALS.MASTER_BENCH_SEAT)
	aru_bench_release(token)

## --- T066 N01-3 transient Aru bench scene -------------------------------------------------------
func aru_bench_slot(token:String) -> int:
	return int(aru_bench.get("sitters",{}).get(token,-1))

## Stand up. The primary leaving ends the whole scene (the friend only visits the primary's seat).
func aru_bench_release(token:String) -> void:
	if aru_bench.is_empty() or not aru_bench.sitters.has(token):return
	if int(aru_bench.sitters[token])==ARU_BENCH.PRIMARY:aru_bench={}
	else:
		aru_bench.sitters.erase(token)

func _aru_bench_seated(token:String,slot:int) -> bool:
	var person:Dictionary=state.players.get(token,{})
	if person.is_empty() or not active_tokens.has(token) or str(person.get("region",REGIONS.HOME))!=REGIONS.HOME or person.has(RESIDENT_GOALS.VOYAGE_START):return false
	var spot:=ARU_BENCH.feet(aru_bench.anchor,slot)
	return Vector2(float(person.x),float(person.y)).distance_to(spot)<=ARU_BENCH.SEAT_TOLERANCE and (_region!=REGIONS.HOME or can_stand(spot))

## Drop sitters that stood, walked, travelled, disconnected, were displaced, or whose seat stopped being valid.
## Runs in HOME orientation (tick, act, snapshot); never touches saved state.
func aru_bench_prune() -> void:
	if aru_bench.is_empty():return
	var previous:=_region
	switch_region(REGIONS.HOME)
	var site:=Village.resident_cell(state,"aru")
	var valid:bool=aru_bench.site==site and aru_bench_slot_primary()!=""
	if valid:
		for token:String in aru_bench.sitters.keys():
			if not _aru_bench_seated(token,int(aru_bench.sitters[token])):
				if int(aru_bench.sitters[token])==ARU_BENCH.PRIMARY:valid=false
				aru_bench.sitters.erase(token)
	if not valid or aru_bench_slot_primary()=="":aru_bench={}
	if previous!=REGIONS.HOME:switch_region(previous)

func aru_bench_slot_primary() -> String:
	for token:String in aru_bench.get("sitters",{}):
		if int(aru_bench.sitters[token])==ARU_BENCH.PRIMARY:return token
	return ""

## Raw view with tokens (Session hashes them). {} when idle.
func aru_bench_scene() -> Dictionary:
	aru_bench_prune()
	if aru_bench.is_empty():return {}
	return {"anchor":aru_bench.anchor,"sitters":aru_bench.sitters.duplicate()}

func _aru_bench_anchor(token:String,site:Vector2i) -> Vector2i:
	for anchor:Vector2i in ARU_BENCH.candidates(site):
		var clear:=true
		for dx in range(2):
			var tile:=anchor+Vector2i(dx,0)
			var tile_key:=key(tile)
			if blocked(tile) or resource(tile)!="" or state.crops.has(tile_key) or state.objects.has(tile_key) or state.roofs.has(tile_key) or state.ground.get(tile_key,{}).get("owner_visit",false) or tile in RESIDENT_GOALS.ARU_PARK_SLOTS.values():
				clear=false
				break
		if not clear:continue
		var spots:Array[Vector2]=[ARU_BENCH.feet(anchor,ARU_BENCH.PRIMARY),ARU_BENCH.feet(anchor,ARU_BENCH.FRIEND)]
		for spot in spots:
			if not can_stand(spot) or not can_enter_room_floor(token,spot):clear=false
		if not clear:continue
		for other:String in active_tokens:
			var neighbour:Dictionary=state.players.get(other,{})
			if other==token or neighbour.is_empty() or str(neighbour.get("region",REGIONS.HOME))!=REGIONS.HOME:continue
			var at:=Vector2(float(neighbour.x),float(neighbour.y))
			for spot in spots:
				if at.distance_to(spot)<ARU_BENCH.CLEARANCE or at.distance_to(ARU_BENCH.npc_feet(anchor))<ARU_BENCH.CLEARANCE:clear=false
		if clear:return anchor
	return Vector2i(-1,-1)

func _aru_bench_action(token:String,player:Dictionary,p:Vector2i,action:String,extra:String) -> Dictionary:
	switch_region(REGIONS.HOME)
	aru_bench_prune()
	var site:=Village.resident_cell(state,"aru")
	var feet:=Vector2(float(player.x),float(player.y))
	var seated:=aru_bench_slot(token)
	# Region, exact Aru cell and reach are checked before any feedback so no UI/notice leaks from far away.
	if not extra.is_empty() or player_region(token)!=REGIONS.HOME or p!=site or player.has(RESIDENT_GOALS.VOYAGE_START) \
		or feet.distance_to(ARU_BENCH.site_center(site))>ARU_BENCH.REACH:
		return fail("請到渡口找阿榆。")
	if action==RESIDENT_GOALS.ARU_REST_LEAVE:
		if seated<0:return ok("你已經不在長椅上了。")
		aru_bench_release(token)
		return ok("你起身，把長椅留給渡口的風。")
	if seated>=0:return ok("你已經坐在長椅上了。")
	var trusted:=RESIDENT_BOND.stage(player,"aru")>=3
	var slot:=ARU_BENCH.PRIMARY
	if aru_bench.is_empty():
		if not trusted:return fail("阿榆和島民坐下後，朋友就能過來一起休息。")
		var anchor:=_aru_bench_anchor(token,site)
		if anchor==Vector2i(-1,-1):return fail("長椅旁暫時沒有空位。")
		aru_bench={"anchor":anchor,"site":site,"sitters":{}}
	else:
		slot=ARU_BENCH.FRIEND
		if aru_bench.sitters.size()>=ARU_BENCH.SLOTS:return fail("長椅旁已經坐滿了。")
		var open_spot:=ARU_BENCH.feet(aru_bench.anchor,slot)
		if not can_stand(open_spot) or not can_enter_room_floor(token,open_spot):return fail("旁邊的位子現在坐不下。")
		for other:String in active_tokens:
			var neighbour:Dictionary=state.players.get(other,{})
			if other!=token and not neighbour.is_empty() and str(neighbour.get("region",REGIONS.HOME))==REGIONS.HOME and not aru_bench.sitters.has(other) \
				and Vector2(float(neighbour.x),float(neighbour.y)).distance_to(open_spot)<ARU_BENCH.CLEARANCE:
				return fail("旁邊的位子有人站著，請稍等一下。")
	player.erase("fishing")
	player.erase(RESIDENT_GOALS.MASTER_BENCH_SEAT)
	player.erase(REGIONS.Springs.REST_SEAT_KEY)
	player.erase(TEA_HOUSE_INTERIOR.SEAT_KEY)
	player.erase(RESIDENT_GOALS.DIANDIAN_SEAT_KEY)
	var spot:=ARU_BENCH.feet(aru_bench.anchor,slot)
	player.x=spot.x
	player.y=spot.y
	aru_bench.sitters[token]=slot
	# Trust holders qualify immediately; a guest below trust never gains the quest key or any reward.
	if trusted:player[RESIDENT_GOALS.ARU_REST_KEY]=float(state.time)
	return ok("你坐下來，和阿榆一起聽著渡口的風。" if slot==ARU_BENCH.PRIMARY else "你在朋友身旁坐下，一起聽著渡口的風。")

func _rest_join(player:Dictionary,token:String,p:Vector2i,extra:String) -> Dictionary:
	var springs=REGIONS.Springs
	if _region!=springs.REGION or springs.in_inn(player) or not springs.REST_SEATS.has(extra) or p!=springs.REST_SEATS[extra]:
		return fail("請走到暖泉溪畔的座位旁。")
	var primary_key:String=extra
	var friend_key:String=springs.REST_FRIEND_PREFIX+extra
	var current:=str(player.get(springs.REST_SEAT_KEY,""))
	if current==friend_key:return ok("正在和朋友並肩坐著。移動即可起身。")
	if current==primary_key:return fail("你已經坐在這個位子上了。")
	var anchor:Vector2=springs.rest_spot(friend_key)
	if Vector2(float(player.x),float(player.y)).distance_to(anchor)>springs.REST_REACH:return fail("再靠近一點，才能坐到旁邊。")
	if not _rest_seat_taken(token,primary_key):return fail("旁邊沒有人在這裡休息。")
	if _rest_seat_taken(token,friend_key):return fail("旁邊的位子有人坐了。")
	player.erase("fishing")
	player.erase(RESIDENT_GOALS.MASTER_BENCH_SEAT)
	player.erase(RESIDENT_GOALS.DIANDIAN_SEAT_KEY)
	player[springs.REST_SEAT_KEY]=friend_key
	player.x=anchor.x
	player.y=anchor.y
	return ok("在旁邊坐下來。移動即可起身。")

func move_player(token: String, direction: Vector2, dt: float) -> void:
	if not state.players.has(token): return
	var p: Dictionary = state.players[token]
	if p.has(RESIDENT_GOALS.VOYAGE_START):return
	var pos := Vector2(p.x, p.y)
	switch_region(player_region(token))
	if _region==REGIONS.HOME and not direction.is_zero_approx() and Rect2(WANGAN_MEMORY.HOUSE_WALL).grow(0.22).has_point(pos):
		if WANGAN_MEMORY.courtyard_available(state) and not can_stand(pos):
			var yard:=safe_arrival(Vector2(WANGAN_MEMORY.COURT_SIGN)+Vector2(0.5,0.5),token)
			if yard!=Vector2.ZERO:pos=yard
	if _region==TEA_CERAMICS.MAOKONG and not direction.is_zero_approx() \
		and Rect2(Vector2(TEA_REVISIT.HOUSE_SITE),Vector2.ONE).grow(0.22).has_point(pos) \
		and TEA_REVISIT.house_open(state) and not can_stand(pos):
		var by_table:=safe_arrival(Vector2(TEA_REVISIT.HOUSE_SITE+Vector2i.DOWN)+Vector2(0.5,0.5))
		if by_table!=Vector2.ZERO:pos=by_table
	# 石殼蟹: the side cart can turn solid under someone's feet when the last legacy build on
	# its cells is cleared. Step them out to the open floor below instead of leaving them stuck.
	if _region==CRAB.REGION and not direction.is_zero_approx() \
		and Rect2(Vector2(CRAB.CART),Vector2.ONE).grow(0.22).has_point(pos) \
		and crab_available() and not can_stand(pos):
		var by_cart:=safe_arrival(Vector2(CRAB.CART+Vector2i.DOWN)+Vector2(0.5,0.5),token)
		if by_cart!=Vector2.ZERO:pos=by_cart
	if _region==PORTER.REGION and not direction.is_zero_approx() and Rect2(Vector2(PORTER.CRATE),Vector2.ONE).grow(0.22).has_point(pos):
		if porter_site_open() and PORTER.site_clear(state) and not can_stand(pos):
			var by_crate:=safe_arrival(PORTER.DELIVERY,token)
			if by_crate!=Vector2.ZERO:pos=by_crate
	if _region==MEADOW.REGION and not direction.is_zero_approx() and state.get("picnic",false) and not can_stand(pos) and MEADOW.site_clear(state):
		for tile:Vector2i in MEADOW.FOOTPRINT:
			if not Rect2(Vector2(tile),Vector2.ONE).grow(0.22).has_point(pos):continue
			var by_table:=safe_arrival(Vector2(tile)+Vector2(0.5,1.5),token)
			if by_table!=Vector2.ZERO:pos=by_table
			break
	var next := pos + direction.limit_length()*MOVE_TILES_PER_SECOND*dt
	if direction.length_squared()>0.01:
		p.erase("fishing")
		p.erase(RESIDENT_GOALS.MASTER_BENCH_SEAT)
		p.erase(REGIONS.Springs.REST_SEAT_KEY)
		p.erase(TEA_HOUSE_INTERIOR.SEAT_KEY)
		p.erase(RESIDENT_GOALS.DIANDIAN_SEAT_KEY)
		aru_bench_release(token)
	# Separate axes; corners of a small foot box must all remain passable.
	var edges:Dictionary=state.get("edges",{})
	var horizontal:=Vector2(next.x,pos.y)
	if horizontal!=pos and can_stand(horizontal) and not EDGE_FOOT_SWEEP.blocks_axis(pos,horizontal,edges,SIZE,INDUSTRY.FOOT_BOX) and can_enter_room_floor(token,horizontal,pos) and can_enter_mud_alcove(token,horizontal,pos):pos.x=next.x
	var vertical:=Vector2(pos.x,next.y)
	if vertical!=pos and can_stand(vertical) and not EDGE_FOOT_SWEEP.blocks_axis(pos,vertical,edges,SIZE,INDUSTRY.FOOT_BOX) and can_enter_room_floor(token,vertical,pos) and can_enter_mud_alcove(token,vertical,pos):pos.y=next.y
	p.x=pos.x
	p.y=pos.y
	if _shy_watch.has(token) and SHY.watch_hold(_shy_watch[token],pos).is_empty():_shy_watch.erase(token)
	if _crab_watch.has(token) and (_region!=CRAB.REGION or not CRAB.near(pos,CRAB.CRAB)):_crab_watch.erase(token)
	if _region==MINES.MUD_REGION and p.has("mud_duel"):
		var duel:Dictionary=p.mud_duel
		if float(state.time)<float(duel.strike_at) and absf(pos.x-float(duel.origin_x))>=0.65:
			duel.dodged=true
	switch_region(REGIONS.HOME)

func _stroll_route(token:String,sign:Vector2i) -> Array:
	if not can_stand(Vector2(sign)+Vector2(0.5,0.5)):return []
	var route:Array=[key(sign)]
	var origin:=sign
	for site:String in LANTERN_STROLL.ORDER:
		var finish:Vector2i=LANTERN_STROLL.SITES[site].cell
		var leg:=_stroll_route_leg(token,origin,finish)
		if leg.is_empty():return []
		for cell:Vector2i in leg:route.append(key(cell))
		origin=finish
	return route

func _stroll_route_leg(token:String,origin:Vector2i,destination:Vector2i) -> Array[Vector2i]:
	return walk_route(token,origin,[destination],LANTERN_STROLL.ROUTE_BOUNDS,true)

func walk_route(token:String,origin:Vector2i,destinations:Array[Vector2i],bounds:Rect2i,public_only:=false) -> Array[Vector2i]:
	if destinations.is_empty() or origin in destinations or not bounds.has_point(origin):return []
	var queue:Array[Vector2i]=[origin]
	var visited:Dictionary={origin:origin}
	var index:=0
	while index<queue.size():
		var cell:=queue[index]
		index+=1
		for offset:Vector2i in [Vector2i.DOWN,Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT]:
			var next:=cell+offset
			if not bounds.has_point(next) or visited.has(next) or not _activity_can_step(token,cell,next):continue
			if public_only and state.ground.get(key(next),{}).get("owner_visit",false):continue
			visited[next]=cell
			if next in destinations:
				var path:Array[Vector2i]=[]
				var cursor:=next
				while cursor!=origin:
					path.push_front(cursor)
					cursor=visited[cursor]
				return path
			queue.append(next)
	return []

func _activity_can_step(token:String,origin:Vector2i,destination:Vector2i) -> bool:
	var start:=Vector2(origin)+Vector2(0.5,0.5)
	var finish:=Vector2(destination)+Vector2(0.5,0.5)
	return can_stand(finish) and not EDGE_FOOT_SWEEP.blocks_axis(start,finish,state.get("edges",{}),SIZE,INDUSTRY.FOOT_BOX) and can_enter_room_floor(token,finish,start)

func can_stand(pos: Vector2) -> bool:
	if not EDGE_FOOT_SWEEP.can_stand(pos,state.get("edges",{}),SIZE,INDUSTRY.FOOT_BOX):return false
	# Several adjacent corners usually occupy the same tile. Check that tile once.
	var previous:Variant=null
	for offset:Vector2 in INDUSTRY.FOOT_BOX:
		var v: Vector2=pos+offset
		var tile:=Vector2i(floori(v.x),floori(v.y))
		if tile==previous:continue
		if blocked(tile):return false
		previous=tile
	return true

static func edge_door_points(snapshot:Dictionary,pos:Vector2) -> Dictionary:
	var edges:Dictionary=snapshot.get("edges",{})
	var points:Dictionary={}
	if edges.is_empty() or not pos.is_finite():return points
	var origin:=Vector2i(pos.floor())
	for y in range(origin.y-2,origin.y+3):
		for x in range(origin.x-2,origin.x+3):
			var at:=Vector2i(x,y)
			for side in [EDGE_GRID.SIDE_N,EDGE_GRID.SIDE_W]:
				var edge:=EDGE_GRID.key(at,side,SIZE)
				if edges.get(edge,{}).get("type")!="edge_door":continue
				var center:=Vector2(at)+(Vector2(0.5,0) if side==EDGE_GRID.SIDE_N else Vector2(0,0.5))
				if pos.distance_squared_to(center)<1.6*1.6:points["edge_door:"+edge]=center
	return points

func can_enter_room_floor(token:String,to:Vector2,from:=Vector2.INF) -> bool:
	if token.is_empty() or _region!=REGIONS.HOME:return true
	var floor_piece:Dictionary=state.ground.get(key(Vector2i(to.floor())),{})
	if not floor_piece.get("owner_visit",false) or floor_piece.get("owner")==token or floor_piece.get("visit_guest")==token:return true
	if from==Vector2.INF:return false
	# A visitor already inside when access changes can still walk out.
	var previous:Dictionary=state.ground.get(key(Vector2i(from.floor())),{})
	return previous.get("owner_visit",false) and previous.get("owner")==floor_piece.get("owner")

func can_enter_mud_alcove(token:String,to:Vector2,from:Vector2) -> bool:
	return _region!=MINES.MUD_REGION or to.y>=MINES.MUD_ALCOVE_EDGE or from.y<MINES.MUD_ALCOVE_EDGE or int(state.players[token].get("mud_alcove",0))>=1

func visit_restriction_problem(token:String,area:Dictionary) -> String:
	if area.cells.is_empty():return "請選擇可站立的地板。"
	if not area.sealed and (area.truncated or area.area>MAX_OUTDOOR_VISIT_TILES):
		return "戶外私人地塊最多可設定 %d 格相連地板。"%MAX_OUTDOOR_VISIT_TILES
	for spot:Vector2i in area.cells:
		if state.ground[key(spot)].owner!=token or protected(spot) or PUBLIC_BUILD_PLOT.has_point(spot):
			return "只能限制全由自己鋪設、且避開公共通道的地塊。"
		if spot in [Vector2i(SPAWN),Vector2i(WANGAN_COAST.FERRY_LANDING),Vector2i(REGIONS.spawn(REGIONS.HOME)),REGIONS.exit_cell(REGIONS.HOME)]:
			return "出生點和出入口需保持開放。"
		if not area.sealed and VILLAGE_LAYOUT.path_at(Vector2(spot)+Vector2(0.5,0.5)):
			return "渡口的步道需保持開放。"
	return ""

func _water_chime_ring(token:String,tile:Vector2i,extra:String)->Dictionary:
	var person:Dictionary=state.players[token]
	var region:=player_region(token)
	var target:=key(tile)
	var chime:Dictionary=_layers_of(region).get("objects",{}).get(target,{})
	var distance:=Vector2(person.x,person.y).distance_to(Vector2(tile)+Vector2(0.5,0.5))
	if not extra.is_empty() or person.has(RESIDENT_GOALS.VOYAGE_START) or distance>WALL_FIXTURES.WATER_CHIME_REACH or chime.get("type")!=WALL_FIXTURES.WATER_LISTENING_CHIME:
		return fail("請靠近聽水風鈴再輕搖。")
	return {"ok":true,"message":"叮——聽水風鈴輕輕響了一聲。","region":region,"tile":target}

## T12 不完美的茶亭: a read-only inspect of the built structure's story memento (any of its nine
## cells). Nothing is written: no materials, no teleport, no clock, no receipt, no save.
func _pavilion_inspect(token:String,tile:Vector2i,extra:String)->Dictionary:
	var person:Dictionary=state.players[token]
	var region:=player_region(token)
	var objects:Dictionary=_layers_of(region).get("objects",{})
	var part:Dictionary=objects.get(key(tile),{})
	var distance:float=Vector2(float(person.x),float(person.y)).distance_to(Vector2(tile)+Vector2(0.5,0.5))
	if not extra.is_empty() or person.has(RESIDENT_GOALS.VOYAGE_START) or distance>INDUSTRY.PAVILION_REACH or str(part.get("type",""))!=INDUSTRY.IMPERFECT_TEA_PAVILION or INDUSTRY.square_part(part)<0:
		return fail("請走近不完美的茶亭再細看。")
	return {"ok":true,"message":PAVILION.memento_message(person),"region":region,"tile":key(station_anchor(objects,tile))}

## 打瞌睡石像 (B4 north cave only). Shared gate: region, depth unlock, target cell, reach.
func _guardian_gate(token:String,p:Vector2i,extra:String,target_ok:bool) -> String:
	var person:Dictionary=state.players[token]
	if not extra.is_empty() or person.has(RESIDENT_GOALS.VOYAGE_START):return "無效的石像操作。"
	if player_region(token)!=GUARDIAN.REGION or not state.get("picnic",false) or int(state.mine_depths.unlocked)<GUARDIAN.DEPTH:
		return "請到第四層礦道北側的小洞。"
	if not target_ok or not GUARDIAN.near(Vector2(float(person.x),float(person.y)),p):return "再走近一點。"
	return ""

func _guardian_record(person:Dictionary) -> Dictionary:
	var record=person.get(GUARDIAN_FIELD)
	if not GUARDIAN.valid(record):return GUARDIAN.fresh()
	return {"round":int(record.round),"calm":int(record.calm),"claimed":bool(record.claimed)}

func guardian_trial_forget(token:String)->void:
	_guardian_trials.erase(token)

func guardian_trial_view(token:String)->Dictionary:
	return GUARDIAN_TRIAL.view(_guardian_trials.get(token,{}))

func _guardian_trial_action(token:String,tile:Vector2i,extra:String)->Dictionary:
	if state.get("world_mode")!="adventure":return fail("冒險模式才能挑戰石像。")
	var reason:=_guardian_gate(token,tile,"",tile==GUARDIAN.GUARDIAN)
	if not reason.is_empty():return fail(reason)
	var actor:Dictionary=state.players[token]
	var at:=Vector2(actor.x,actor.y)
	if not GUARDIAN_TRIAL.ARENA.has_point(at):return fail("請走進石像前的洞室。")
	var record:=_guardian_record(actor)
	if GUARDIAN.awake(record):return fail("石像已經醒了。")
	var run:Dictionary=_guardian_trials.get(token,{})
	var phase:=int(run.get("phase",-1))
	if extra==GUARDIAN_TRIAL.START and phase in [-1,GUARDIAN_TRIAL.Phase.MISSED]:
		_guardian_trials[token]=GUARDIAN_TRIAL.begin(at,float(state.time))
		return ok("石像舉起石掌了，退到標記外。")
	if extra==GUARDIAN_TRIAL.FINISH and phase==GUARDIAN_TRIAL.Phase.SAFE:
		record.round=GUARDIAN.ROUNDS
		actor[GUARDIAN_FIELD]=record
		_guardian_trials.erase(token)
		_guardian_entered.erase(token)
		return ok("石像收起石掌，眨著眼睛讓開了身後的晶砂。")
	return fail("等兩次落掌都結束，再走近石像。")

## Private reply for the acting player only. The hum order (`notes`) exists nowhere else:
## not in state, not in snapshots.
static func _guardian_result(res:Dictionary) -> Dictionary:
	var record:Dictionary=res.record
	var view:={"outcome":str(res.outcome),"round":int(record.round),"calm":int(record.calm),"claimed":bool(record.claimed),"entered":(res.entered as Array).size()}
	if res.has("notes"):view["notes"]=(res.notes as Array).duplicate(true)
	return {"ok":bool(res.ok),"message":str(res.message),"guardian":view}

## Free, unlimited and read-only: no receipt, no journal row, no save. The order is derived
## from the server-side token, so the same player always hears the same hum.
func _guardian_listen(token:String,p:Vector2i,extra:String) -> Dictionary:
	var blocked:=_guardian_gate(token,p,extra,p==GUARDIAN.GUARDIAN)
	if not blocked.is_empty():return fail(blocked)
	var out:=_guardian_result(GUARDIAN.listen(token,_guardian_record(state.players[token])))
	out.guardian.entered=(_guardian_entered.get(token,[]) as Array).size()
	return out

func _guardian_action(token:String,action:String,p:Vector2i,extra:String) -> Dictionary:
	var bell:=GUARDIAN.bell_at(p)
	var blocked:=_guardian_gate(token,p,extra,bell>=0 if action=="guardian_ring" else p==GUARDIAN.GUARDIAN)
	if not blocked.is_empty():return fail(blocked)
	var person:Dictionary=state.players[token]
	var record:=_guardian_record(person)
	var res:Dictionary
	match action:
		"guardian_ring":res=GUARDIAN.ring(token,record,_guardian_entered.get(token,[]),bell)
		"guardian_sit":res=GUARDIAN.sit(record)
		"guardian_claim":res=GUARDIAN.claim(record)
		_:return fail("無效的石像操作。")
	if res.ok and res.has("reward"):
		var inv:Dictionary=person.inventory
		var item:String=res.reward.item
		var count:int=res.reward.count
		if int(inv.get(item,0))>1000000000-count:return fail("背包中的%s已達上限，謝禮先留在石像身後。"%NAMES[item])
		give(inv,item,count)
	if res.ok:
		person[GUARDIAN_FIELD]=(res.record as Dictionary).duplicate(true)
		if (res.entered as Array).is_empty():_guardian_entered.erase(token)
		else:_guardian_entered[token]=(res.entered as Array).duplicate()
	var out:=_guardian_result(res)
	if action=="guardian_ring":out.guardian["bell"]=bell
	return out

## 害羞菇 (B2 east nook only, optional, never a gate). Call with the actor's region loaded.
func shy_available() -> bool:
	return bool(state.get("picnic",false)) and SHY.available(_region,int(state.mine_depths.unlocked))

func _shy_record(person:Dictionary) -> Dictionary:
	var record=person.get(SHY_FIELD)
	if not SHY.valid(record):return SHY.fresh()
	return {"stage":int(record.stage),"claimed":bool(record.claimed)}

## The quiet-wait anchor is host memory only: never saved, dropped by walking off or leaving.
func shy_forget(token:String) -> void:
	_shy_watch.erase(token)
	_shy_spores.erase(token)

func shy_spore_view(token:String)->Dictionary:
	return SHY_SPORES.view(_shy_spores.get(token,{}),float(state.time))

func _shy_spore_action(token:String,tile:Vector2i,extra:String)->Dictionary:
	if state.get("world_mode")!="adventure" or not shy_available():return fail("請到冒險模式第二層礦道東側。")
	var person:Dictionary=state.players[token]
	var record:=_shy_record(person)
	var at:=Vector2(person.x,person.y)
	if tile!=SHY.MUSHROOM or not SHY_SPORES.ARENA.has_point(at) or not SHY.near(at):return fail("走近害羞菇再互動。")
	if SHY.open(record):return fail("害羞菇已經放心了。")
	var run:=shy_spore_view(token)
	if extra==SHY_SPORES.ENTER:
		if int(run.get("phase",-1)) in [SHY_SPORES.Phase.WARNING,SHY_SPORES.Phase.PASSING,SHY_SPORES.Phase.FINISHED]:
			return fail("這一輪已開始，留意地上的孢子路線。")
		_shy_spores[token]=SHY_SPORES.begin(at,float(state.time))
		return ok("帽子抖了抖。孢子要飄出來了，換到另一側。")
	if extra==SHY_SPORES.FINISH and int(run.get("phase",-1))==SHY_SPORES.Phase.FINISHED:
		person[SHY_FIELD]={"stage":2,"claimed":false}
		_shy_spores.erase(token)
		return ok("兩團孢子都飄過去了，害羞菇探頭朝你笑。")
	return fail("等兩團孢子飄過，再去看看害羞菇。")

func _shy_reply(token:String,ok_value:bool,message:String,record:Dictionary,outcome:String,remaining:float=0.0,cues:Array=[]) -> Dictionary:
	var watch:Dictionary=_shy_watch.get(token,{})
	return {"ok":ok_value,"message":message,"shy":{"outcome":outcome,"stage":int(record.stage),"claimed":bool(record.claimed),
		"remaining":remaining,"since":float(watch.get("since",-1.0)),"x":float(watch.get("x",0.0)),"y":float(watch.get("y",0.0)),"cues":cues.duplicate()}}

## `shy_wait` / `shy_claim` (interact key) and the ordinary `water` tool on the mushroom cell.
## Position and time are the host's own; a too-early splash or a cancelled wait costs nothing.
func _shy_action(token:String,action:String,p:Vector2i,extra:String) -> Dictionary:
	var person:Dictionary=state.players[token]
	var record:=_shy_record(person)
	if not extra.is_empty():return _shy_reply(token,false,"無效的害羞菇操作。",record,"invalid")
	if not shy_available():return _shy_reply(token,false,"請到第二層礦道東側的小洞。",record,"unavailable")
	if p!=SHY.MUSHROOM:return _shy_reply(token,false,"請靠近害羞菇。",record,"far")
	var pos:=Vector2(float(person.x),float(person.y))
	var res:Dictionary
	match action:
		SHY.WAIT_ACTION:res=SHY.wait(record,_shy_watch.get(token,{}),pos,float(state.time))
		SHY.WATER_ACTION:res=SHY.water(record,pos)
		SHY.CLAIM_ACTION:res=SHY.claim(record,pos)
		_:return _shy_reply(token,false,"無效的害羞菇操作。",record,"invalid")
	if res.ok and res.has("reward"):
		var inv:Dictionary=person.inventory
		var item:String=res.reward.item
		var count:int=res.reward.count
		if int(inv.get(item,0))>1000000000-count:
			return _shy_reply(token,false,"背包中的%s已達上限，小禮物先留在帽子下。"%NAMES[item],record,"full")
		give(inv,item,count)
	if res.ok:
		if res.record!=record or person.has(SHY_FIELD):person[SHY_FIELD]=(res.record as Dictionary).duplicate(true)
		if (res.watch as Dictionary).is_empty():_shy_watch.erase(token)
		else:_shy_watch[token]=(res.watch as Dictionary).duplicate(true)
	return _shy_reply(token,bool(res.ok),str(res.message),res.record,str(res.outcome),float(res.remaining),res.cues)

## 石殼蟹 (B5 east cave only, optional, never a gate). Call with the actor's region loaded.
## Hidden while an older save still has something built on one of its three cells.
func crab_available() -> bool:
	return crab_site_open() and CRAB.site_clear(state)

## Region and world progress only (picnic held, B5 opened); ignores what is built on the cells.
func crab_site_open() -> bool:
	return bool(state.get("picnic",false)) and CRAB.available(_region,int(state.get("mine_depths",{}).get("unlocked",0)))

func _crab_record(person:Dictionary) -> Dictionary:
	var record=person.get(CRAB_FIELD)
	if not CRAB.valid(record):return CRAB.fresh()
	return {"stage":int(record.stage),"claimed":bool(record.claimed)}

## The adventure wait cycle is host memory only: dropped by walking off, leaving or disconnecting.
func crab_forget(token:String) -> void:
	_crab_watch.erase(token)

func _crab_reply(token:String,ok_value:bool,message:String,record:Dictionary,outcome:String,cues:Array=[],missing:Dictionary={}) -> Dictionary:
	var open_at:=CRAB.shell_open_at(_crab_watch.get(token,{}))
	var view:={"outcome":outcome,"stage":int(record.stage),"claimed":bool(record.claimed),"cues":cues.duplicate(),"missing":missing.duplicate(),
		"open_at":-1.0,"close_at":-1.0}
	if open_at!=-INF:
		view.open_at=open_at
		view.close_at=open_at+CRAB.SHELL_WINDOW
	return {"ok":ok_value,"message":message,"crab":view}

## `crab_survey` / `crab_repair` / `crab_claim` (interact key), plus `crab_shell` wait|tap in
## adventure worlds. Position, bag and time are the host's own. Only a successful repair spends
## materials, and only from the actor's own bag; every refusal costs and changes nothing.
func _crab_action(token:String,action:String,p:Vector2i,extra:String) -> Dictionary:
	var person:Dictionary=state.players[token]
	var record:=_crab_record(person)
	var shell:=action==CRAB.SHELL_ACTION
	if (shell and extra not in [CRAB.SHELL_WAIT,CRAB.SHELL_TAP]) or (not shell and not extra.is_empty()):
		return _crab_reply(token,false,"無效的石殼蟹操作。",record,"invalid")
	if not crab_site_open():
		return _crab_reply(token,false,"請到第五層礦道東側的小洞。",record,"unavailable")
	if not CRAB.site_clear(state):return _crab_reply(token,false,"小洞靠牆的角落被東西占住了，清開後石殼蟹才會出來。",record,"occupied")
	if shell and state.get("world_mode")!="adventure":return _crab_reply(token,false,"在這座島上，修好旁邊的小礦車就可以了。",record,"life_mode")
	if p!=(CRAB.CART if action==CRAB.REPAIR_ACTION else CRAB.crab_cell(record)):
		return _crab_reply(token,false,"請靠近小礦車。" if action==CRAB.REPAIR_ACTION else "請靠近石殼蟹。",record,"far")
	var pos:=Vector2(float(person.x),float(person.y))
	var inv:Dictionary=person.inventory
	var watch:Dictionary=_crab_watch.get(token,{})
	var now:=float(state.time)
	var res:Dictionary
	match action:
		CRAB.SURVEY_ACTION:res=CRAB.survey(record,pos)
		CRAB.REPAIR_ACTION:res=CRAB.repair(record,pos,inv)
		CRAB.CLAIM_ACTION:res=CRAB.claim(record,pos)
		CRAB.SHELL_ACTION:res=CRAB.shell_wait(record,watch,pos,now) if extra==CRAB.SHELL_WAIT else CRAB.shell_tap(record,watch,pos,now)
		_:return _crab_reply(token,false,"無效的石殼蟹操作。",record,"invalid")
	if res.ok and res.has("reward"):
		var item:String=res.reward.item
		var count:int=res.reward.count
		if int(inv.get(item,0))>1000000000-count:
			return _crab_reply(token,false,"背包中的%s已達上限，小禮物先留在礦車裡。"%NAMES[item],record,"full")
		give(inv,item,count)
	if res.ok:
		var consume:Dictionary=res.consume
		# The module already checked the bag; re-check here so a spend can never go negative.
		for item:String in consume:
			if int(inv.get(item,0))<int(consume[item]):return _crab_reply(token,false,"修理材料不足。",record,"short",[],CRAB.missing(inv))
		for item:String in consume:give(inv,item,-int(consume[item]))
		if res.record!=record or person.has(CRAB_FIELD):person[CRAB_FIELD]=(res.record as Dictionary).duplicate(true)
		if shell:
			if (res.watch as Dictionary).is_empty():_crab_watch.erase(token)
			else:_crab_watch[token]=(res.watch as Dictionary).duplicate(true)
		elif CRAB.settled(res.record):_crab_watch.erase(token)
	return _crab_reply(token,bool(res.ok),str(res.message),res.record,str(res.outcome),res.cues,res.missing)

func _read_chest_history(token: String, tile: Vector2i, extra: String) -> Dictionary:
	var person: Dictionary = state.players[token]
	var region := player_region(token)
	var tile_key:=key(tile)
	var layers:=_layers_of(region)
	var box: Dictionary = layers.objects.get(tile_key,{})
	var distance := Vector2(person.x, person.y).distance_to(Vector2(tile) + Vector2(0.5, 0.5))
	if not extra.is_empty() or person.has(RESIDENT_GOALS.VOYAGE_START) or distance > 3.2 or box.get("type") not in SAVE_SCHEMA.CHEST_HISTORY.BOXES:
		return fail("請靠近木箱再查看操作紀錄。")
	if not PLOT_PERMISSIONS.can_withdraw(token,box,layers.ground.get(tile_key,{})).ok:
		return fail("需要取出權限才能查看這個木箱的操作紀錄。")
	return {"ok": true, "message": "", "rows": box.get(SAVE_SCHEMA.CHEST_HISTORY.FIELD, []).duplicate(true)}

func porter_site_open()->bool:
	return bool(state.get("picnic",false)) and PORTER.available(_region,int(state.mine_depths.unlocked))

func porter_team()->Array:
	if state.get("world_mode")!="adventure":return []
	return active_tokens.keys().filter(func(token):return player_region(token)==PORTER.REGION)

func porter_watcher(team:Array,actor:String,index:int)->String:
	var marker:Vector2=PORTER.WATCH_POINTS[index]
	for member:String in team:
		if member==actor:continue
		var person:Dictionary=state.players[member]
		if Vector2(person.x,person.y).distance_to(marker)<=PORTER.WATCH_RADIUS:return member
	return ""

func _porter_action(token:String,action:String,tile:Vector2i,extra:String)->Dictionary:
	if not extra.is_empty():return fail("無效的搬運操作。")
	if not porter_site_open():return fail("到第六層礦道才能遇見搬運鼠。")
	if not PORTER.site_clear(state):return fail("搬運路上有東西擋住了，清出路後搬運鼠才會來。")
	var person:Dictionary=state.players[token]
	var stage:=int(person.get(PORTER.FIELD,PORTER.Stage.WAITING))
	var inventory:Dictionary=person.inventory
	var fits:=ITEM_CATALOG.can_hold(PORTER.REWARD_ITEM,int(inventory.get(PORTER.REWARD_ITEM,0))+PORTER.REWARD_COUNT)
	var result:=PORTER.advance(stage,action,tile,Vector2(person.x,person.y),fits)
	if not result.ok:return fail(result.message)
	var member:=""
	var index:=PORTER.watch_index(stage)
	var team:=porter_team()
	if index>=0 and team.size()>=2:
		member=porter_watcher(team,token,index)
		if member.is_empty():return fail("請另一位島民站在「%s」的標記上。"%PORTER.WATCH_LABELS[index])
	person[PORTER.FIELD]=result.stage
	if int(result.reward)>0:give(inventory,PORTER.REWARD_ITEM,int(result.reward))
	if stage==PORTER.Stage.TO_CRATE and not member.is_empty():
		var watcher:Dictionary=state.players[member]
		if int(watcher.get(PORTER.FIELD,PORTER.Stage.WAITING))<PORTER.Stage.DELIVERED:
			watcher[PORTER.FIELD]=PORTER.Stage.DELIVERED
		return ok("安全卸貨了！護送與守望的島民都能向搬運鼠領謝禮。")
	return ok(result.message)

func _meadow_adventurers()->Dictionary:
	var positions:Dictionary={}
	for member:String in active_tokens:
		if player_region(member)!=MEADOW.REGION:continue
		var p:Dictionary=state.players[member]
		var at:=Vector2(p.x,p.y)
		if int(p.get(MEADOW.FIELD,0))<MEADOW.ALL_TABLES and at.distance_to(MEADOW.FACE)<=MEADOW_ADVENTURE.ROOM_RADIUS:
			positions[member]=at
	return positions

func meadow_adventure_view(token:String)->Dictionary:
	return MEADOW_ADVENTURE.public_view(_meadow_round,token)

func _meadow_adventure_action(token:String,tile:Vector2i,extra:String)->Dictionary:
	if state.get("world_mode")!="adventure" or _region!=MEADOW.REGION or not state.get("picnic",false) or int(state.mine_depths.unlocked)<MEADOW.DEPTH:
		return fail("只有冒險模式的提燈大廳能開始這場挑戰。")
	if not MEADOW.site_clear(state):return fail("供品台附近有東西擋住了。")
	var positions:=_meadow_adventurers()
	if not positions.has(token):return fail("靠近毛球，或先領取你已經完成的謝禮。")
	var at:Vector2=positions[token]
	var now:=float(state.time)
	var round:=MEADOW_ADVENTURE.step(_meadow_round,positions,now)
	match extra:
		MEADOW_ADVENTURE.WAKE:
			if not round.is_empty():return fail("這輪已經開始。")
			if tile!=MEADOW.CENTER or at.distance_to(MEADOW.FACE)>MEADOW.REACH:return fail("請走近巨大毛球守護者。")
			var nearby:=positions.keys().filter(func(member):return positions[member].distance_to(MEADOW.FACE)<=MEADOW_ADVENTURE.TEAM_RADIUS)
			_meadow_round=MEADOW_ADVENTURE.begin(nearby,now)
			return ok("毛球要踏地了！快離開圈起的地面。")
		MEADOW_ADVENTURE.LIGHT,MEADOW_ADVENTURE.CALM:
			var result:=MEADOW_ADVENTURE.light(round,token,tile,at) if extra==MEADOW_ADVENTURE.LIGHT else MEADOW_ADVENTURE.calm(round,token,tile,at)
			if not result.ok:return fail(result.message)
			_meadow_round=result.round
			for member:String in result.completed:
				state.players[member][MEADOW.FIELD]=MEADOW.ALL_TABLES
			return ok(result.message)
	return fail("請重新選擇毛球的挑戰操作。")

func _meadow_action(token:String,action:String,tile:Vector2i,extra:String)->Dictionary:
	if not extra.is_empty():return fail("請重新選擇供奉操作。")
	if _region!=MEADOW.REGION or not state.get("picnic",false) or int(state.mine_depths.unlocked)<MEADOW.DEPTH:
		return fail("請到第十五層的提燈大廳。")
	if not MEADOW.site_clear(state):return fail("供品台附近有東西擋住了。")
	var person:Dictionary=state.players[token]
	var record:=int(person.get(MEADOW.FIELD,0))
	var at:=Vector2(person.x,person.y)
	var inventory:Dictionary=person.inventory
	if record==MEADOW.CLAIMED:return fail("你已經收過毛球的謝禮。")
	if action==MEADOW.CLAIM:
		if tile!=MEADOW.CENTER or at.distance_to(MEADOW.FACE)>MEADOW.REACH:return fail("請走近毛球再領謝禮。")
		if record!=MEADOW.ALL_TABLES:return fail("先在三座供品台各放一顆蘿蔔。")
		for item:String in MEADOW.REWARD:
			if not ITEM_CATALOG.can_hold(item,int(inventory.get(item,0))+MEADOW.REWARD[item]):return fail("背包空出位置後，再回來領毛球的謝禮。")
		for item:String in MEADOW.REWARD:give(inventory,item,MEADOW.REWARD[item])
		person[MEADOW.FIELD]=MEADOW.CLAIMED
		return ok("毛球蹭了蹭你的手，送你兩份含金礦料和兩份晶砂。")
	if token in _meadow_round.get("eligible",[]):return fail("挑戰中請先和同伴點亮供品台。")
	var index:=MEADOW.TABLES.find(tile)
	if index<0 or at.distance_to(MEADOW.table_feet(tile))>MEADOW.REACH:return fail("請走近一座供品台。")
	if MEADOW.table_full(record,index):return fail("這座已經放過供品了。")
	if int(inventory.get(MEADOW.ITEM,0))<1:return fail("需要一顆蘿蔔才能放上供品台。")
	give(inventory,MEADOW.ITEM,-1)
	person[MEADOW.FIELD]=record|(1<<index)
	if person[MEADOW.FIELD]==MEADOW.ALL_TABLES:return ok("三座供品都放好了。毛球醒了，走到牠身邊看看。")
	return ok("放上一顆蘿蔔，毛球的耳朵動了一下。")

func act(token: String, request_id: String, action: String, p: Vector2i, extra: String="") -> Dictionary:
	if not state.players.has(token): return {"ok":false,"message":"尚未加入世界"}
	if request_id.length()<1 or request_id.length()>80: return {"ok":false,"message":"無效請求"}
	if action==WALL_FIXTURES.WATER_CHIME_RING:
		return _water_chime_ring(token,p,extra)
	if action==INDUSTRY.PAVILION_INSPECT:
		return _pavilion_inspect(token,p,extra)
	if action=="guardian_listen":
		return _guardian_listen(token,p,extra)
	if action==SAVE_SCHEMA.CHEST_HISTORY.READ_ACTION:
		return _read_chest_history(token,p,extra)
	# C13: `build` + "mill:<0-3>[@style]" places the new 3x3 mill with that facing. A plain "mill" keeps the
	# legacy meaning (consume a held mill_kit -> 1x1) and only becomes a new facing-0 mill without a kit.
	# The suffix is stripped here, so undo intent / auto roofs / receipts all see the plain "mill" id.
	var mill_facing := -1
	if action=="build" and extra.begins_with(INDUSTRY.MILL+":"):
		var facing_text:=extra.substr(INDUSTRY.MILL.length()+1)
		var facing_at:=facing_text.find("@")
		var facing_value:=facing_text if facing_at<0 else facing_text.left(facing_at)
		if facing_value not in ["0","1","2","3"]:return fail("磨坊的入口方向只能是 0 到 3")
		mill_facing=int(facing_value)
		extra=INDUSTRY.MILL+("" if facing_at<0 else facing_text.substr(facing_at))
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
	aru_bench_prune()
	if player.receipts.has(request_id): return player.receipts[request_id]
	if player.has(RESIDENT_GOALS.VOYAGE_START) and action!=RESIDENT_GOALS.VOYAGE_ACTION:return fail("試航中，先返回碼頭再操作。")
	if player.has(RESIDENT_GOALS.MASTER_BENCH_SEAT) and action not in [RESIDENT_GOALS.MASTER_BENCH_SIT,RESIDENT_GOALS.INSCRIBE_ACTION,"inn_pool_sit","move_object","remove","claim_hotpot",INDUSTRY.BEACH_SIT,INDUSTRY.LOUNGER_REST,INDUSTRY.SHELL_SIT,INDUSTRY.HOLLOW_REST,INDUSTRY.MUSHROOM_SIT,INDUSTRY.MUSHROOM_SERVE,INDUSTRY.MUSHROOM_EAT,INDUSTRY.MUSHROOM_TAKE]:return fail("起身後就能繼續操作。")
	var before := state.duplicate(true)
	var region := player_region(token)
	var bench_before:=aru_bench.duplicate(true)
	# Host-memory bell phrase lives outside `state`; roll it back with a failed save.
	var guardian_entered_before:Array=(_guardian_entered.get(token,[]) as Array).duplicate()
	var guardian_trial_before:Dictionary=_guardian_trials.get(token,{})
	# Same for the 害羞菇 quiet-wait anchor: a start / peek whose save fails must not stick.
	var shy_watch_before:Dictionary=(_shy_watch.get(token,{}) as Dictionary).duplicate(true)
	var shy_spores_before:Dictionary=_shy_spores.get(token,{})
	# And the 石殼蟹 adventure wait cycle.
	var crab_watch_before:Dictionary=(_crab_watch.get(token,{}) as Dictionary).duplicate(true)
	var meadow_round_before:=_meadow_round
	if region==PARTY_CART.REGION and action not in [PARTY_CART.ACTION,"rescue"]:
		return fail("活動坑道只開放礦車、道岔與落石操作。")
	var builds_before:=int(player.get("builds",0))
	switch_region(region)
	# Decided BEFORE the base action: remove must know what it is about to target.
	var touched := _auto_roof_touched(action,p,extra)
	var undo_intent := _undo_intent(action,p,extra)
	var quest_types := _undo_quest_types(token,action,extra)
	var result: Dictionary
	if action in TRADE_ACTIONS:result=_trade_action(token,request_id,action,extra)
	elif action==UNDO_ACTION:result=_undo_apply(token,extra)
	else:result=_apply(token,action,p,extra,build_style,mill_facing)
	var natural_gather:bool=result.get("natural_gather",false)
	result.erase("natural_gather")
	if result.ok and action=="build" and not build_style.is_empty():
		var layer := BUILD_STYLES.expected_layer(extra)
		state[layer][key(p)].style=build_style
	if result.ok and player_region(token)!=region:
		player.erase(REGIONS.Springs.REST_SEAT_KEY)
		player.erase(TEA_HOUSE_INTERIOR.SEAT_KEY)
		player.erase(RESIDENT_GOALS.DIANDIAN_SEAT_KEY)
		if region==REGIONS.HOME:LANTERN_STROLL.return_lantern(state,token)
	if result.ok and str(state.animal.get(CHICKEN_CUDDLE.FIELD,""))==token and (player_region(token)!=REGIONS.HOME or player.has(RESIDENT_GOALS.VOYAGE_START) or player.has(RESIDENT_GOALS.MASTER_BENCH_SEAT) or player.has(REGIONS.Springs.REST_SEAT_KEY)):
		CHICKEN_CUDDLE.clear(state.animal)
	if result.ok and str(state.animal.get(CHICKEN_FEED_FOLLOW.FIELD,""))==token and player_region(token)!=REGIONS.HOME:
		state.animal.erase(CHICKEN_FEED_FOLLOW.FIELD)
	if result.ok and str(state.livestock.get("cow",{}).get(COW_CARE.FIELD,""))==token and (player_region(token)!=REGIONS.HOME or player.has(RESIDENT_GOALS.VOYAGE_START) or player.has(RESIDENT_GOALS.MASTER_BENCH_SEAT) or player.has(REGIONS.Springs.REST_SEAT_KEY)):
		COW_CARE.clear(state)
	if not result.ok:
		switch_region(REGIONS.HOME)
		aru_bench=bench_before
		# Most rejected base actions have not mutated anything. Keep their live
		# references intact; only replace state when rollback is actually needed.
		if state!=before:_restore(before)
		_ledger_reject(action,token,request_id,str(result.get("message","")))
		return result
	if result.ok and not touched.is_empty():
		var roof := _reconcile_auto_roofs(token,region,before,touched)
		if not roof.ok:
			_restore(before)
			aru_bench=bench_before
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
			_undo_capture(token,region,action,str(undo_intent.label),before,builds_before,not result.get("guest_dismantle",false))
		result.erase("guest_dismantle")
		player=state.players[token]
		Collections.note_acquisitions(player,before.players[token].inventory,CROPS,RECIPES)
		if not staged_trade.is_empty():
			for other:String in state.players:
				if other!=token:Collections.note_acquisitions(state.players[other],before.players[other].inventory,CROPS,RECIPES)
		state.committed += 1
		player.receipts[request_id]=result
		# Keep a bounded retry window; transport session IDs reject old sessions.
		while player.receipts.size()>128: player.receipts.erase(player.receipts.keys()[0])
		# T015: the journal entry lives in the same state save() writes, so the
		# change, its receipt and its journal row commit (or roll back) together.
		var journal_entry:=_ledger_commit(action,token,request_id,before,result)
		if not save():
			_restore(before)
			aru_bench=bench_before
			if guardian_entered_before.is_empty():_guardian_entered.erase(token)
			else:_guardian_entered[token]=guardian_entered_before
			if guardian_trial_before.is_empty():_guardian_trials.erase(token)
			else:_guardian_trials[token]=guardian_trial_before
			if shy_watch_before.is_empty():_shy_watch.erase(token)
			else:_shy_watch[token]=shy_watch_before
			if shy_spores_before.is_empty():_shy_spores.erase(token)
			else:_shy_spores[token]=shy_spores_before
			if crab_watch_before.is_empty():_crab_watch.erase(token)
			else:_crab_watch[token]=crab_watch_before
			_meadow_round=meadow_round_before
			if not journal_entry.is_empty():_ledger_reject(action,token,request_id,SAVE_FAILED_MSG,true)
			return {"ok":false,"message":SAVE_FAILED_MSG}
		_ledger_pending.clear()
		if natural_gather:_finish_gather_work(region,p,token,bool(result.get("gather_continue",false)))
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
	if action in ["sell","ship","buy"]:
		var player:Dictionary=state.players[token]
		var stage:=int(player.get(RESIDENT_GOALS.CROP_TRADE_KEY,0))
		if stage!=int(before.players[token].get(RESIDENT_GOALS.CROP_TRADE_KEY,0)):
			var step:="sale" if stage==RESIDENT_GOALS.CROP_SOLD else "seed"
			TRANSACTION_LEDGER.remember_first_shop_trade(player,step,entry,float(state.time))
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

const MINING_PICKS := ["precision_pick","iron_pick","copper_pick","reinforced_pick"]
const MINING_PICK_EFFECTS := {
	"copper_pick":{"cooldown":9.0,"energy":1.0},
	"iron_pick":{"cooldown":8.0,"energy":0.8},
	"precision_pick":{"cooldown":7.0,"energy":0.65},
}
const FORESTRY_AXES := ["precision_axe","iron_axe","copper_axe"]
const FARM_HOES := ["precision_hoe","iron_hoe","copper_hoe"]
const WATERING_CANS := ["precision_can","iron_can","copper_can"]
const SEED_POUCHES := ["precision_seed_pouch","iron_seed_pouch","copper_seed_pouch"]
const HARVEST_SICKLES := ["precision_sickle","iron_sickle","copper_sickle"]
const FORESTRY_AXE_EFFECTS := {
	"copper_axe":{"impact":2,"hardwood_bonus":0},
	"iron_axe":{"impact":3,"hardwood_bonus":0},
	"precision_axe":{"impact":3,"hardwood_bonus":1},
}

static func active_mining_pick(inventory:Dictionary) -> String:
	return _best_owned_tool(inventory,MINING_PICKS)

static func _best_owned_tool(inventory:Dictionary,tiers:Array) -> String:
	for item:String in tiers:
		if int(inventory.get(item,0))>0:return item
	return ""

static func gathering_tool_upgrade(action:String,inventory:Dictionary) -> String:
	if action=="harvest":return _best_owned_tool(inventory,HARVEST_SICKLES)
	if action=="seed":return _best_owned_tool(inventory,SEED_POUCHES)
	if action=="fish":return _best_owned_tool(inventory,FishingTracking.ROD_TIERS)
	if action=="hoe":return _best_owned_tool(inventory,FARM_HOES)
	if action=="water":return _best_owned_tool(inventory,WATERING_CANS)
	if action=="axe":return _best_owned_tool(inventory,FORESTRY_AXES)
	if action=="pick":
		var pick:=active_mining_pick(inventory)
		if MINING_PICK_EFFECTS.has(pick):return pick
	return ""

static func trade_items() -> Dictionary:
	var items := NAMES.duplicate()
	for item in MINING_PICKS+FORESTRY_AXES+FARM_HOES+WATERING_CANS+SEED_POUCHES+HARVEST_SICKLES+FishingTracking.ROD_TIERS+["gold_sample","tiller","seeder","harvester"]:
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
	if a.has(RESIDENT_GOALS.VOYAGE_START) or b.has(RESIDENT_GOALS.VOYAGE_START):return false
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
	if action in ["build_edge","remove_edge"]:
		var edge:=EDGE_CONSTRUCTION.decode(action,p,extra,SIZE)
		if not edge.is_empty():touched.assign(edge.cells)
	elif action=="build":
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
	if has_hanging_pot(k):return "objects"
	if state.roofs.has(k) and not is_auto_roof(state.roofs[k]):return "roofs"
	if state.objects.has(k):return "objects"
	if state.ground.has(k):return "ground"
	return ""

func has_hanging_pot(k:String) -> bool:
	return state.objects.get(k,{}).get("type")==ROOF_FIXTURES.HANGING_POT

## Runs in the actor's region after a successful base action. Plans the roof
## delta with the pure planner, validates every affected inventory, then applies
## roofs + staged inventories together. Returns {ok, message} on failure (caller
## restores `before`), or {ok, added, removed, summary}.
func _reconcile_auto_roofs(token: String, region: String, before: Dictionary, touched: Array[Vector2i]) -> Dictionary:
	var source: Dictionary = before if region==REGIONS.HOME else before.regions.get(region,{})
	if source.is_empty() and region!=REGIONS.HOME:return {"ok":false,"message":"區域資料有誤，這次沒有施工"}
	var plan:Dictionary=AUTO_ROOF_PLAN.reconcile(source,state,touched,token,BUILD.roof)
	if not plan.ok:return {"ok":false,"message":plan.message}
	var add:Dictionary=plan.add
	var remove:Array=plan.remove
	if add.is_empty() and remove.is_empty():return {"ok":true,"added":0,"removed":0,"summary":""}
	if not state.players.has(token):return {"ok":false,"message":"無法確認付款者，這次沒有施工"}
	for roof_key in add:
		if not allows_public_build(token,cell(roof_key)):return fail(PUBLIC_BUILD_DENIED)
		var base=state.ground.get(roof_key)
		var roof=add[roof_key]
		if state.roofs.has(roof_key) or not ROOM_ENCLOSURE.is_floor_piece(base):return {"ok":false,"message":"屋頂施工計畫有誤，這次沒有施工"}
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
const UNDO_FOOT := INDUSTRY.FOOT_BOX

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
		"build_edge","remove_edge":
			var edge:=EDGE_CONSTRUCTION.decode(action,p,extra,SIZE)
			if edge.is_empty():return {}
			var kind:String=edge.kind if action=="build_edge" else state.edges.get(edge.id,{}).get("type","")
			if EDGE_CONSTRUCTION.NAMES.has(kind):
				return {"label":("拆除" if action=="remove_edge" else "")+str(EDGE_CONSTRUCTION.NAMES[kind])}
		"build":
			if BUILD.has(extra):return {"label":str(BUILD[extra].name)}
		"build_area":
			var parts:=extra.split("|")
			if parts.size()==3 and BUILD.has(parts[0]):return {"label":str(BUILD[parts[0]].name)}
		"remove":
			if state.forest.has(k) or (state.crops.has(k) and not has_glass_roof(k) and not has_hanging_pot(k)):return {}
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
	# C12: using any cell of a 2x2 公共廚房灶台 uses the whole object (all four cells), live or just removed.
	for objects in [layers.objects,prior]:
		if objects is Dictionary and objects.get(tile,{}).get("type")==INDUSTRY.KITCHEN_STOVE:
			for c in KITCHEN_STOVE.cells_at(station_anchor(objects,p)):tiles[key(c)]=true
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
		elif not _undo_watch_matches(entry):
			_undo_close(entry,"changed")
			changed=true
	return changed

## Records the actor's LAST construction after a successful build/build_area/
## remove/move_object (base + auto roofs already applied, oriented HOME). Any
## capture problem still replaces the previous entry, with an untracked marker,
## so an older construction never resurfaces as "last".
func _undo_capture(token: String, region: String, action: String, label: String, before: Dictionary, builds_before: int, reversible:=true) -> void:
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
	var expected:int={"build":1,"remove":0,"move_object":0,"build_edge":1,"remove_edge":0}.get(action,-1)
	# build_area and blueprint record a whole multi-piece transaction; each keeps
	# its own bound (25 vs MAX_BLUEPRINT_BUILDS) so neither widens the other.
	var multi_max:int={"build_area":CONSTRUCTION_HISTORY.MAX_AREA,"blueprint":CONSTRUCTION_HISTORY.MAX_BLUEPRINT_BUILDS,
		"edge_blueprint":CONSTRUCTION_HISTORY.MAX_EDGE_BLUEPRINT_BUILDS}.get(action,0)
	var builds_ok:=(builds_delta>=1 and builds_delta<=multi_max) if multi_max>0 else builds_delta==expected
	if multi_max>0:label="%s ×%d"%[label,builds_delta]
	label=label.left(CONSTRUCTION_HISTORY.MAX_LABEL_LEN)
	var fallback_builds:=maxi(expected,1 if action=="build_area" else 0)
	if action in ["blueprint","edge_blueprint"]:fallback_builds=clampi(builds_delta,1,multi_max)
	var entry:={"id":"c%d"%serial,"region":region,"action":action,"label":label,
		"created_utc":created,"expires_utc":created+CONSTRUCTION_HISTORY.WINDOW_SECONDS,
		"status":"invalid","reason":"untracked","builds":builds_delta if builds_ok else fallback_builds,
		"record":{},"watch":{}}
	if builds_ok and reversible:
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
	var b:={"ground":prior.ground,"objects":prior.objects,"roofs":prior.roofs,"edges":prior.get("edges",{}),"players":players_before}
	var a:={"ground":current.ground,"objects":current.objects,"roofs":current.roofs,"edges":current.get("edges",{}),"players":players_after}
	var captured:=CONSTRUCTION_UNDO.capture(b,a,token,{"pending":0})
	if not captured.ok:return {"ok":false}
	var record:Dictionary=captured.record
	var watched:=CONSTRUCTION_HISTORY.build_watch(prior,current,record.changes,SIZE)
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
	for id in _undo_watch_memos.keys():
		if not keep.has(id):_undo_watch_memos.erase(id)

var _undo_watch_memos:Dictionary={}

func _undo_watch_matches(entry:Dictionary) -> bool:
	var memo:Dictionary=_undo_watch_memos.get_or_add(entry.id,{})
	return CONSTRUCTION_HISTORY.watch_matches_cached(_layers_of(entry.region),entry.watch,memo)

var _undo_preview_proposal:Dictionary={}
var _undo_preview_roof_layers:Dictionary={}
var _undo_preview_roof_problem:=""

## Read-only full check of the actor's last record. MUST run oriented to the
## record's region. Returns {ok, message, entry, prepared, left}.
func _undo_check(token: String, id: String, preview:=false) -> Dictionary:
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
	var unchanged:=_undo_watch_matches(entry) if preview else CONSTRUCTION_HISTORY.watch_matches(_layers_of(entry.region),entry.watch)
	if not unchanged:return _undo_no(CONSTRUCTION_HISTORY.reason_text("changed"))
	var current:={"ground":state.ground,"objects":state.objects,"roofs":state.roofs,"edges":state.edges,"players":state.players}
	var prepared:=CONSTRUCTION_UNDO.prepare(current,token,record,revisions,_undo_preview_proposal if preview else null)
	if not prepared.ok:return _undo_no(str(prepared.message))
	if int(state.players[token].get("builds",0))<int(entry.builds):return _undo_no(UNDO_MSG_STATS)
	var problem:=_undo_restore_problem(token,record.changes,prepared.layers,preview)
	if problem!="":return _undo_no(problem)
	return {"ok":true,"message":CONSTRUCTION_HISTORY.TEXT_READY,"entry":entry,"prepared":prepared,"left":timing.left}

static func _record_snack_shelf_stock(stock:Dictionary,shelf:Variant)->void:
	if not shelf is Dictionary or shelf.get("type")!=INDUSTRY.TEA_SNACK_SHELF or INDUSTRY.snack_total(shelf)==0:
		return
	var signature:=CONSTRUCTION_HISTORY.fingerprint([shelf.owner,shelf.get("cabinet_shared",false),shelf[INDUSTRY.SNACK_FIELD]])
	stock[signature]=int(stock.get(signature,0))+1

## "" when the staged inverse is placeable; read-only. Region oriented.
func _undo_restore_problem(token: String, changes: Dictionary, staged: Dictionary, preview:bool) -> String:
	var solid:={}
	var limited:={}
	var topology:Array[Vector2i]=[]
	var seen_topology:={}
	var kitchen:Array[Vector2i]=[]
	var restored_edges:Dictionary={}
	var shelf_live:Dictionary={}
	var shelf_restored:Dictionary={}
	if _region==REGIONS.HOME:kitchen=PUBLIC_KITCHEN.site_cells(state)
	for id:String in changes.get("edges",{}):
		var restored:Variant=changes.edges[id].before
		if restored==null:
			var mount_problem:=WALL_FIXTURES.removal_problem(staged.objects,state.edges,id)
			if not mount_problem.is_empty():return mount_problem
		for c:Vector2i in EDGE_GRID.cells_of(id,SIZE):
			if c in kitchen:return PUBLIC_KITCHEN.MSG_LOCKED
			if restored!=null:
				if not is_land(c) or water(c) or protected(c) or not essential_cell_reason(state,_region,c).is_empty():return UNDO_MSG_TERRAIN
				if not allows_public_build(token,c):return PUBLIC_BUILD_DENIED
				var permission:=PLOT_PERMISSIONS.can_place(self,token,c,str(restored.type))
				if not permission.ok:return permission.message
				if EDGE_CONSTRUCTION._mill_route(self,c):return EDGE_CONSTRUCTION.MSG_MILL
			if not seen_topology.has(c):
				seen_topology[c]=true
				topology.append(c)
		if restored!=null:restored_edges[id]=restored
	for layer in CONSTRUCTION_UNDO.LAYERS:
		var layer_changes:Dictionary=changes[layer]
		for tile in layer_changes:
			var parsed:=CONSTRUCTION_HISTORY.parse_tile(str(tile))
			if not parsed.ok:return CONSTRUCTION_UNDO.MSG_RECORD
			var c:Vector2i=parsed.cell
			if layer_changes[tile].before!=null and not allows_public_build(token,c):return PUBLIC_BUILD_DENIED
			if layer=="objects" and layer_changes[tile].before!=null:
				var floor_permission:=PLOT_PERMISSIONS.placement_floor(self,token,c)
				if not floor_permission.ok:return floor_permission.message
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
			var hanger:Dictionary=staged.objects.get(tile,{})
			if layer in ["objects","roofs"] and hanger.get("type")==ROOF_FIXTURES.HANGING_POT and not ROOF_FIXTURES.supported(staged.roofs.get(tile),str(hanger.owner)):
				return ROOF_FIXTURES.REMOVE_MESSAGE if layer=="roofs" else ROOF_FIXTURES.SUPPORT_MESSAGE
			if layer=="objects":
				_record_snack_shelf_stock(shelf_live,state.objects.get(tile))
				_record_snack_shelf_stock(shelf_restored,restored)
				if state.objects.get(tile,{}).get("type")==INDUSTRY.BEACH_CHAIR and _seat_occupied(station_anchor(state.objects,c)):
					return INDUSTRY.BEACH_BUSY
				if state.objects.get(tile,{}).get("type")==INDUSTRY.BAMBOO_LOUNGER and _seat_occupied(station_anchor(state.objects,c)):
					return INDUSTRY.LOUNGER_BUSY
				if state.objects.get(tile,{}).get("type")==INDUSTRY.SHELL_TABLE and _seat_occupied(c):
					return INDUSTRY.SHELL_BUSY
				if state.objects.get(tile,{}).get("type")==INDUSTRY.HOLLOW_BED and _seat_occupied(station_anchor(state.objects,c)):
					return INDUSTRY.HOLLOW_BUSY
				if state.objects.get(tile,{}).get("type")==INDUSTRY.MUSHROOM_STOOL and _seat_occupied(c):
					return INDUSTRY.MUSHROOM_STOOL_BUSY
				if state.objects.get(tile,{}).get("type")==INDUSTRY.WOOD_CHAIR and _seat_occupied(c):
					return INDUSTRY.WOOD_CHAIR_BUSY
				if state.objects.get(tile,{}).get("type")==INDUSTRY.INDIGO_CUSHION and _seat_occupied(c):
					return INDUSTRY.INDIGO_CUSHION_BUSY
				if state.objects.get(tile,{}).get("type") in RESIDENT_GOALS.INDEPENDENT_TWO_SEATS and _seat_occupied(master_bench_anchor(state.objects,c)):
					return RESIDENT_GOALS.two_seat_busy(state.objects[tile].type)
				if state.objects.get(tile,{}).get("type") in INDUSTRY.FOUR_SEAT_TABLES and _seat_occupied(station_anchor(state.objects,c)):
					return INDUSTRY.MUSHROOM_TABLE_BUSY
				if state.objects.get(tile,{}).get("type")==INDUSTRY.COAST_CART:
					if state.objects.get(key(station_anchor(state.objects,c)),{}).get("market_cart_open",false):return INDUSTRY.CART_BUSY
				var mounted:Dictionary=staged.objects.get(key(c+Vector2i.DOWN),{})
				if mounted.get("type") in WALL_FIXTURES.KINDS and not WALL_FIXTURES.has_support(staged.objects,c+Vector2i.DOWN,str(mounted.owner),str(mounted.type),staged.edges):
					return WALL_FIXTURES.remove_message(str(mounted.type))
			if restored==null:continue
			if not is_land(c) or water(c) or protected(c):return UNDO_MSG_TERRAIN
			var kind:=str(restored.get("type",""))
			if layer=="roofs":
				var below=staged.ground.get(tile)
				if kind==GREENHOUSE_GLASS.XINGHE_ROOF:
					var plot:Dictionary=state.crops.get(tile,{})
					if not plot.is_empty() and plot.get("owner")!=restored.get("owner"):return UNDO_MSG_TERRAIN
					if below is Dictionary and below.get("owner")!=restored.get("owner"):return UNDO_MSG_TERRAIN
					if resource(c)!="" or WEATHER.is_indoor(_region):return UNDO_MSG_TERRAIN
					continue
				if not ROOM_ENCLOSURE.is_floor_piece(below):return UNDO_MSG_ROOF
				if not is_auto_roof(restored) and below.get("owner")!=restored.get("owner"):return UNDO_MSG_ROOF
				continue
			if resource(c)!="" or (state.crops.has(tile) and kind!=ROOF_FIXTURES.HANGING_POT) or state.forest.has(tile):return UNDO_MSG_TERRAIN
			if layer!="objects":continue
			if kind in WALL_FIXTURES.KINDS and not WALL_FIXTURES.has_support(staged.objects,c,str(restored.owner),kind,staged.edges):
				return WALL_FIXTURES.support_message(kind)
			if (kind in UNDO_SOLID and not INDUSTRY.is_folded_passage(restored)) or (kind=="door" and not restored.get("open",false)):solid[tile]=true
			if kind=="mine_drill" and (_region not in MINE_DRILL.REGIONS or int(state.mine_depths.unlocked)<5 or MINE_DRILL.placement(c)<0 or int(restored.get("dir",-1))!=MINE_DRILL.placement(c)):return UNDO_MSG_LOCKED
			if kind=="waterworks" and int(state.mine_depths.unlocked)<4:return UNDO_MSG_LOCKED
			if kind in KITCHEN_GATED and not kitchen_opened():return MILL_LOCKED_MSG
			if kind==INDUSTRY.IMPERFECT_TEA_PAVILION and INDUSTRY.square_part(restored)==0:
				if not PAVILION.unlocked(state.players.get(str(restored.get("owner","")),{})):return UNDO_MSG_LOCKED
				var essential:=pavilion_site_problem(c)
				if not essential.is_empty():return essential
			# C13: a restored new mill needs a walkable cell in front of its entrance in the restored layout, and
			# nothing solid may come back onto the front cell of a mill that stays.
			if kind==INDUSTRY.MILL and INDUSTRY.square_part(restored)==0:
				var mill_front:=c+INDUSTRY.mill_front_offset(INDUSTRY.mill_facing(restored))
				if _mill_entrance_walled(staged.edges,c,INDUSTRY.mill_facing(restored)):return INDUSTRY.MILL_ENTRANCE_BLOCKED
				var front_object:Dictionary=staged.objects.get(key(mill_front),{})
				var front_solid:bool=(str(front_object.get("type","")) in UNDO_SOLID and not INDUSTRY.is_folded_passage(front_object)) or (front_object.get("type")=="door" and not front_object.get("open",false))
				if front_solid or not is_land(mill_front) or water(mill_front) or resource(mill_front) in ["tree","rock"]:return UNDO_MSG_LOCKED
			if (kind in UNDO_SOLID or kind=="door") and not INDUSTRY.is_folded_passage(restored) and INDUSTRY.is_mill_front(staged.objects,c):return UNDO_MSG_LOCKED
			# Beimen: only chests on chest-socket cells may ever come back.
			if _region==SALT_PAN.REGION and (kind not in SALT_BOXES or SALT_PAN.chest_socket_lot(c)<0):return SALT_PAN.REJECT_MESSAGE
			if kind=="water_pump" and not INDUSTRY.near_river(self,c):return UNDO_MSG_LOCKED
			limited["%s|%s"%[kind,str(restored.get("owner",""))]]=[kind,str(restored.get("owner",""))]
	if shelf_live!=shelf_restored:return INDUSTRY.SNACK_UNDO_MESSAGE
	# Per-owner limits on the staged layers (region-local like build; drills and
	# waterworks also world-wide; one drill per mine layer).
	var local_limits:={"sprinkler":SPRINKLER_LIMIT,"medium_sprinkler":SPRINKLER_LIMIT,"large_sprinkler":SPRINKLER_LIMIT,"forester":FORESTRY.LIMIT,"conveyor":LOGISTICS.BELT_LIMIT}
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
		var problem:=_undo_roof_problem(token,staged,topology,preview)
		if not problem.is_empty():return problem
	# Every active player in this region, the actor included.
	if not solid.is_empty():
		for active in regional_tokens():
			var who:Dictionary=state.players[active]
			for offset in UNDO_FOOT:
				var v:Vector2=Vector2(float(who.x),float(who.y))+offset
				if solid.has(key(Vector2i(floori(v.x),floori(v.y)))):return UNDO_MSG_OCCUPIED
	if not restored_edges.is_empty():
		for active in regional_tokens():
			var who:Dictionary=state.players[active]
			if not EDGE_FOOT_SWEEP.can_stand(Vector2(who.x,who.y),restored_edges,SIZE,INDUSTRY.FOOT_BOX):return UNDO_MSG_OCCUPIED
	return ""

func _undo_roof_problem(token:String,staged:Dictionary,topology:Array[Vector2i],preview:bool) -> String:
	# A reused proposal proves that the current layers, inverse and actor are
	# identical. The roof planner only reads those inputs and the roof recipe.
	if preview and is_same(staged,_undo_preview_roof_layers):return _undo_preview_roof_problem
	var plan:Dictionary=AUTO_ROOF_PLAN.reconcile(state,staged,topology,token,BUILD.roof)
	var problem:=""
	if not plan.ok:problem=str(plan.message)
	elif not plan.add.is_empty() or not plan.remove.is_empty():problem=UNDO_MSG_TOPOLOGY
	if preview:
		_undo_preview_roof_layers=staged
		_undo_preview_roof_problem=problem
	return problem

## Authoritative undo, oriented to the actor's region inside act(). act()
## restores the whole pre-action state on failure or save failure.
func _undo_apply(token: String, id: String) -> Dictionary:
	if id.is_empty() or id.length()>CONSTRUCTION_HISTORY.MAX_ID_LEN:return fail(UNDO_MSG_MISSING)
	var check:=_undo_check(token,id)
	if not check.ok:return fail(str(check.message))
	var entry:Dictionary=check.entry
	var record:Dictionary=entry.record
	var changes:Dictionary=record.changes
	for edge_id:String in changes.get("edges",{}):
		var restored:Variant=changes.edges[edge_id].before
		if restored==null:state.edges.erase(edge_id)
		else:state.edges[edge_id]=restored.duplicate(true)
	for layer in CONSTRUCTION_UNDO.LAYERS:
		var target:Dictionary=state[layer]
		var layer_changes:Dictionary=changes[layer]
		for tile in layer_changes:
			var restored=layer_changes[tile].before
			var current_kind:String=target.get(tile,{}).get("type","")
			if layer=="objects" and current_kind in [INDUSTRY.WOOD_CHAIR,INDUSTRY.INDIGO_CUSHION]+RESIDENT_GOALS.INDEPENDENT_TWO_SEATS and (restored==null or restored.get("type")!=current_kind):
				_master_bench_clear(cell(tile))
			if restored==null:target.erase(tile)
			else:target[tile]=(restored as Dictionary).duplicate(true)
	if _region==REGIONS.HOME:
		var restored_bed:=""
		if entry.action=="move_object":
			for tile:String in changes.objects:
				var restored:Variant=changes.objects[tile].before
				if restored is Dictionary and restored.get("type")==INDUSTRY.CEDAR_BED and INDUSTRY.square_part(restored)==0:
					restored_bed=tile
					break
		for tile:String in changes.objects:
			var previous:Variant=changes.objects[tile].after
			if previous is Dictionary and previous.get("type")==INDUSTRY.CEDAR_BED and INDUSTRY.square_part(previous)==0:
				var owner:Dictionary=state.players[previous.owner]
				if owner.get(INDUSTRY.HOME_REST_FIELD)==tile:
					var current:Dictionary=state.objects.get(tile,{})
					if current.get("type")!=INDUSTRY.CEDAR_BED or INDUSTRY.square_part(current)!=0 or current.get("owner")!=previous.owner:
						if restored_bed.is_empty():owner.erase(INDUSTRY.HOME_REST_FIELD)
						else:owner[INDUSTRY.HOME_REST_FIELD]=restored_bed
			if state.objects.get(tile,{}).get("type") not in RESIDENT_GOALS.DOUBLE_BENCHES+[INDUSTRY.FOOT_BATH,RESIDENT_GOALS.GARDEN_CHAIR,INDUSTRY.SHELL_TABLE,INDUSTRY.HOLLOW_BED,INDUSTRY.MUSHROOM_STOOL,INDUSTRY.WOOD_CHAIR,INDUSTRY.INDIGO_CUSHION]+INDUSTRY.FOUR_SEAT_TABLES:
				_master_bench_clear(cell(tile))
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
	var check:=_undo_check(token,str(entry.id),true)
	switch_region(previous)
	out.available=bool(check.ok)
	out.reason=str(check.message)
	return out

## 礦車搬運坑道是否已對本世界開放：任何已存玩家完成過波波第二階（紀錄裡是合法選項），
## 或已有非空的礦車搬運公開活動（舊世界早已開始）。只讀取既有欄位、不新增存檔欄位，
## 也不回傳是誰完成的。只管進入入口；單人地表 ore_route 不看這個旗標。
func party_cart_unlocked() -> bool:
	if int(PARTY_CART.public_view(state).get("round",0))>0:return true
	var entry:Dictionary=RESIDENT_GOALS.goal("bobo",2)
	var players:Variant=state.get("players")
	if not players is Dictionary:return false
	for token in players:
		var person:Variant=players[token]
		if not person is Dictionary:continue
		var choice:Variant=RESIDENT_GOALS.done(person,"bobo").get(2)
		if choice is String and not RESIDENT_GOALS.option(entry,choice).is_empty():return true
	return false

func _party_cart_portal(token:String,cell:Vector2i,enter:bool) -> Dictionary:
	var player:Dictionary=state.players[token]
	if enter and not party_cart_unlocked():return fail("礦車搬運坑道還封著。幫波波修好動不了的礦車，坑道就會對大家開放。")
	var origin:String=REGIONS.JINGUASHI if enter else PARTY_CART.REGION
	var site:Vector2i=PARTY_CART.SURFACE_PORTAL if enter else PARTY_CART.EXIT
	if _region!=origin or cell!=site or not active_tokens.has(token):
		return fail("請走到礦車搬運坑道的入口。")
	if Vector2(player.x,player.y).distance_to(Vector2(site)+Vector2(0.5,0.5))>3.2:
		return fail("請靠近坑道入口再通行。")
	if int(player.travel_epoch)>=1000000000:return fail("旅行紀錄已達上限。")
	var destination:String=PARTY_CART.REGION if enter else REGIONS.JINGUASHI
	var target:=REGIONS.spawn(destination) if enter else Vector2(PARTY_CART.SURFACE_PORTAL)+Vector2(0.5,1.5)
	switch_region(destination)
	var arrival:=safe_arrival(target,token)
	switch_region(origin)
	if arrival==Vector2.ZERO:return fail("出口附近沒有可站立的空地。")
	if not enter:PARTY_CART.return_member(state,token)
	player.region=destination
	player.travel_epoch=int(player.travel_epoch)+1
	player.x=arrival.x
	player.y=arrival.y
	for field in ["fishing","last_till","last_seed","last_harvest"]:player.erase(field)
	return ok("進入礦車搬運坑道。" if enter else "回到金瓜石山城。")

func _apply(token: String, action: String, p: Vector2i, extra: String, build_style: String = "", mill_facing: int = -1) -> Dictionary:
	var player: Dictionary=state.players[token]
	if action==PARTY_CART.ACTION:
		if extra in ["enter","exit"]:return _party_cart_portal(token,p,extra=="enter")
		return PARTY_CART.apply(state,token,p,extra,_region==PARTY_CART.REGION,active_tokens)
	var cuddler:=CHICKEN_CUDDLE.holder(state,active_tokens)
	if action==CHICKEN_CUDDLE.RELEASE:
		if _region!="home" or cuddler!=token:return fail("現在沒有抱著糯米雞。")
		CHICKEN_CUDDLE.clear(state.animal)
		return ok("輕輕放開，糯米雞回雞圈休息了。")
	if action==CHICKEN_CUDDLE.ACTION:
		if _region!="home" or p!=CHICKEN_CELL or Vector2(player.x,player.y).distance_to(Vector2(CHICKEN_CELL)+Vector2(0.5,0.5))>3.2:return fail("靠近糯米雞的雞圈，才能輕輕抱牠。")
		if not cuddler.is_empty():return fail("糯米雞正被朋友抱著，等牠回來再換你。")
		if float(state.time)-float(state.animal.last_pet)<CHICKEN_CUDDLE.COOLDOWN:return fail("糯米雞剛被照料過，讓牠休息一會兒。")
		state.animal.last_pet=float(state.time)
		state.animal.bond=mini(1000000000,int(state.animal.bond)+1)
		state.animal[CHICKEN_CUDDLE.FIELD]=token
		state.animal.erase(CHICKEN_FEED_FOLLOW.FIELD)
		player.erase("fishing")
		return ok("抱抱糯米雞，牠晃了晃小腳。八秒後會回雞圈，也可以按互動鍵提早放開。")
	if cuddler==token and action in CHICKEN_CUDDLE.HAND_ACTIONS:return fail("雙手正抱著糯米雞，先按互動鍵讓牠回雞圈。")
	if action in ["build_edge","remove_edge","toggle_edge"]:
		if cuddler==token:return fail("雙手正抱著糯米雞，先按互動鍵讓牠回雞圈。")
		if _region!=REGIONS.HOME:return fail("請回到家園再施工或開關木門。")
		return EDGE_CONSTRUCTION.apply(self,token,action,p,extra)
	if not cuddler.is_empty() and action in ["pet","feed"]:return fail("糯米雞正在抱抱，等牠回雞圈再照料。")
	if action=="ferry_news_read":
		if not extra.is_valid_int() or int(extra)!=ISLAND_STORY_RECAP.marker(state):
			return fail("渡口近況有更新，請重新開啟島嶼近況。")
		player.ferry_recap_seen=int(extra)
		return ok("已記下這次查看的渡口近況。")
	if action=="news_read":
		if not extra.is_valid_int():return fail("近況資料有誤。")
		var mask:=int(extra)
		var completed:=island_news_project_mask()
		if mask<0 or mask>ISLAND_NOTES.news_project_limit() or (mask & completed)!=mask:return fail("請重新開啟島嶼近況。")
		player.news_seen=int(player.get("news_seen",0)) | mask
		return ok("已記下這次查看的島嶼近況。")
	if action=="news_note":
		var message:=ISLAND_NOTES.clean(extra)
		if message.is_empty():return fail("請輸入有效留言。")
		var revision:=ISLAND_NOTES.revision(state)
		if revision>=ISLAND_NOTES.REVISION_LIMIT:return fail("留言板已達紀錄上限。")
		var notes:Array=state.get("island_notes",[])
		notes.push_front({"sender":str(player.name),"text":message,"time":float(state.time)})
		if notes.size()>ISLAND_NOTES.LIMIT:notes.pop_back()
		state.island_notes=notes
		state.island_note_revision=revision+1
		return ok("留言已貼到島嶼近況。")
	if action=="news_notes_read":
		if not extra.is_valid_int():return fail("請重新開啟島民留言。")
		var revision:=int(extra)
		if revision<0 or revision>ISLAND_NOTES.revision(state):return fail("請重新開啟島民留言。")
		player.island_note_seen=maxi(int(player.get("island_note_seen",0)),revision)
		return ok("已將這批留言標為讀過。")
	var inv: Dictionary=player.inventory
	if action=="handcraft_rope":
		if not extra.is_empty():return fail("無法辨識這次手作")
		if int(inv.get("fiber",0))<ROPE_FIBER_COST:return fail("製作繩索需要 %d 份纖維"%ROPE_FIBER_COST)
		if int(inv.get("rope",0))>=1000000000:return fail("背包中的繩索已達上限")
		give(inv,"fiber",-ROPE_FIBER_COST)
		give(inv,"rope",1)
		player.crafting_points=mini(1000000000,int(player.get("crafting_points",0))+1)
		return ok("用 %d 份纖維編成 1 條繩索"%ROPE_FIBER_COST)
	if action in ["eat_rice_ball","drink_ginger_tea"]:
		var food:=GINGER_TEA if action=="drink_ginger_tea" else "star_rice_ball"
		var name:String=NAMES[food]
		var highland:bool=food==GINGER_TEA and _region==WARM_SPRINGS.REGION
		var replace_ok:bool=extra==MEAL_BUFF.CONFIRM and highland
		if not extra.is_empty() and not replace_ok:return fail("無法辨識這次食用")
		if _region not in MINES.IDS and not highland:return fail(name+"可在合作礦場恢復體力")
		var has_room:=MEAL_BUFF.whole_points(player)<100
		var now:=float(state.time)
		MEAL_BUFF.expire(player,now)
		var needs_warmth:=highland and not MEAL_BUFF.has(player,MEAL_BUFF.GINGER,now)
		if not has_room and not needs_warmth:return fail("已經暖和，體力也已滿。" if highland else "礦場體力已滿")
		if int(inv.get(food,0))<1:return fail("背包裡沒有"+name)
		if highland and MEAL_BUFF.needs_confirm(player,MEAL_BUFF.GINGER,now) and not replace_ok:
			return fail(MEAL_BUFF.replace_prompt(player,MEAL_BUFF.GINGER,now))
		give(inv,food,-1)
		var restored:=MEAL_BUFF.restore(player,KITCHEN_STOVE.restore_for(food))
		if highland:
			MEAL_BUFF.apply(player,MEAL_BUFF.GINGER,now)
			return ok("喝了暖薑茶，接下來八分鐘會暖和一些。")
		return ok(("喝了" if food==GINGER_TEA else "吃了")+name+"，恢復 %d 點礦場體力"%restored)
	if action==KITCHEN_STOVE.EAT_ACTION:
		# C12 D01-D16: one eaten serving restores exploration stamina (mine_energy, cap 100, never
		# overflows). The star rice ball and ginger tea keep their older actions above. Eating takes
		# no real food from anyone else and needs no stove: only the backpack and a mine.
		# D03: salad also claims the single meal-buff slot (strike cost -5% for 360 s). A different active
		# effect needs the explicit "salad:replace" confirmation; the item id itself is unchanged.
		var eaten:=extra
		var confirmed:=false
		if extra==MEAL_BUFF.SALAD+":"+MEAL_BUFF.CONFIRM:
			eaten=MEAL_BUFF.SALAD
			confirmed=true
		var dish:Dictionary=KITCHEN_STOVE.dish(eaten)
		if dish.is_empty() or eaten in KITCHEN_STOVE.LEGACY_EAT:return fail("無法辨識這次食用")
		var dish_name:String=str(NAMES.get(eaten,eaten))
		if _region not in MINES.IDS:return fail(dish_name+"可在合作礦場恢復體力")
		var room:=100-MEAL_BUFF.whole_points(player)
		var buffed:bool=eaten==MEAL_BUFF.SALAD
		var now:=float(state.time)
		MEAL_BUFF.expire(player,now)
		if room<=0 and not buffed:return fail("礦場體力已滿")
		if room<=0 and MEAL_BUFF.has(player,MEAL_BUFF.SALAD,now):return fail("沙拉效果還在，體力也已滿。")
		if int(inv.get(eaten,0))<1:return fail("背包裡沒有"+dish_name)
		if buffed and not confirmed and MEAL_BUFF.needs_confirm(player,MEAL_BUFF.SALAD,now):
			return fail(MEAL_BUFF.replace_prompt(player,MEAL_BUFF.SALAD,now))
		var gained:=MEAL_BUFF.restore(player,int(dish.restore))
		give(inv,eaten,-1)
		if buffed:
			MEAL_BUFF.apply(player,MEAL_BUFF.SALAD,now)
			return ok("吃了"+dish_name+"，恢復 %d 點礦場體力，採礦耗體 −5%%（6 分鐘）"%gained)
		return ok("吃了"+dish_name+"，恢復 %d 點礦場體力"%gained)
	var k := key(p)
	var dist := Vector2(player.x,player.y).distance_to(Vector2(p)+Vector2(0.5,0.5))
	if action in [MILL_RESTORATION.ACTION,MILL_RESTORATION.SERVICE]:
		if _region!=REGIONS.HOME or dist>3.2 or (p!=MILL_RESTORATION.BOARD and (p!=MILL_RESTORATION.DOOR or not MILL_RESTORATION.site_clear(state))):
			return fail("請到渡口舊磨坊門口，或到公告板找阿榆。")
		if action==MILL_RESTORATION.SERVICE:return MILL_RESTORATION.service(state,player,extra)
		if not extra.is_empty():return fail("請從公告板的磨坊工程交料。")
		return MILL_RESTORATION.repair(state,inv)
	if action=="floor_lamp_toggle":
		var lamp:Dictionary=state.objects.get(key(p),{})
		var lamp_name:String="紙罩茶燈" if lamp.get("type")==INDUSTRY.PAPER_TEA_LAMP else "暖木落地燈"
		if dist>3.2 or lamp.get("type") not in INDUSTRY.SWITCHABLE_LAMPS or not extra.is_empty():return fail("請靠近"+lamp_name+"再操作。")
		if lamp.get("owner")!=token:return fail("只有燈的主人可以調整開關。")
		if lamp.get("lamp_off",false):
			lamp.erase("lamp_off")
			return ok("打開"+lamp_name+"。")
		lamp.lamp_off=true
		return ok("關上"+lamp_name+"。")
	if action in Collections.GALLERY_ACTIONS:
		if _region!=REGIONS.HOME or p!=Vector2i(40,29) or dist>3.2:return fail("請靠近風鈴渡口的公告板管理圖鑑收藏。")
		if not Collections.gallery_item(extra,CROPS,RECIPES):return fail("圖鑑沒有這項普通收藏。")
		var donations:Dictionary=player.get("collection_donations",{})
		var displayed:Array=player.get("collection_display",[])
		if action=="collection_donate":
			if donations.has(extra):return fail("這項收藏已經登錄。")
			if int(inv.get(extra,0))<1 and not Collections.kept_story_item(extra,player):return fail("先取得一份原品。")
			if not Collections.story_item(extra):give(inv,extra,-1)
			donations[extra]=true
			player.collection_donations=donations
			return ok("已登錄 "+str(NAMES.get(extra,extra))+"。")
		if not donations.has(extra):return fail("先完成收藏登錄，再安排展示。")
		if action=="collection_unshow":
			if not displayed.has(extra):return fail("這項收藏目前未展示。")
			displayed.erase(extra)
		else:
			if displayed.has(extra):return fail("這項收藏已在展示。")
			if displayed.size()>=Collections.DISPLAY_CAP:return fail("展示已滿，先撤下一件收藏。")
			displayed.append(extra)
		player.collection_display=displayed
		return ok("已更新公告板的收藏展示。")
	if action==RESIDENT_GOALS.MASTER_BENCH_SIT:
		if dist>3.2 or not extra.is_empty():return fail("請靠近可坐的椅子。")
		return _master_bench_sit(token,player,p)
	if action in [INDUSTRY.BEACH_SIT,INDUSTRY.BEACH_FOLD]:
		var standing:bool=action==INDUSTRY.BEACH_SIT and player.get(RESIDENT_GOALS.MASTER_BENCH_SEAT,{}).get("cell")==key(station_anchor(state.objects,p))
		if dist>3.2 and not standing:return fail("請靠近折疊沙灘椅。")
		return _beach_chair_action(token,player,p,action,extra)
	if action==INDUSTRY.LOUNGER_REST:
		var lying:bool=player.get(RESIDENT_GOALS.MASTER_BENCH_SEAT,{}).get("cell")==key(station_anchor(state.objects,p))
		if dist>3.2 and not lying:return fail("請靠近竹編躺椅。")
		return _bamboo_lounger_rest(token,player,p,extra)
	if action==INDUSTRY.RIVERSIDE_FOLD:
		if dist>3.2:return fail("請靠近河岸屏風。")
		return _riverside_screen_action(token,p,extra)
	if action in [INDUSTRY.SHELL_SIT,INDUSTRY.SHELL_PUT,INDUSTRY.SHELL_TAKE,INDUSTRY.TABLE_VASE_SWAP,INDUSTRY.ROUNDED_EAT]:
		return _shell_table_action(token,player,p,dist,action,extra)
	if action in [INDUSTRY.MUSHROOM_SIT,INDUSTRY.MUSHROOM_SERVE,INDUSTRY.MUSHROOM_EAT,INDUSTRY.MUSHROOM_TAKE]:
		return _four_seat_table_action(token,player,p,action,extra)
	if action==INDUSTRY.HOLLOW_REST:
		return _hollow_bed_rest(token,player,p,extra)
	if action==INDUSTRY.CEDAR_BED:
		return _cedar_bed_action(token,player,p,dist,extra)
	if action=="inn_pool_sit":
		var anchor:=station_anchor(state.objects,p)
		if _region!=REGIONS.HOME or dist>3.2 or state.objects.get(key(anchor),{}).get("type")!=INDUSTRY.FOOT_BATH:
			return fail("請靠近家園的暖石泡腳池。")
		if player.get(RESIDENT_GOALS.MASTER_BENCH_SEAT,{}).get("cell")==key(anchor):
			player.erase(RESIDENT_GOALS.MASTER_BENCH_SEAT)
			return ok("你從泡腳池旁起身。")
		if player.has(RESIDENT_GOALS.MASTER_BENCH_SEAT) or extra not in ["0","1","2","3"]:return fail("請選擇一個座位。")
		return _claim_seat(token,player,{"cell":key(anchor),"side":int(extra)},"坐下來泡泡腳。")
	# A ceiling is its own tile, even over the second half of a table or planter.
	var removal_layer:=_remove_layer(k) if action=="remove" else ""
	var removing_roof:=removal_layer=="roofs"
	var removing_mat:bool=removal_layer=="ground" and state.ground[k].type==INDUSTRY.LEAF_MAT
	if removing_mat:
		p=station_anchor(state.ground,p)
		k=key(p)
	if action==INDUSTRY.MAT_SHADE_ACTION:
		if dist>3.2 or state.ground.get(k,{}).get("type")!=INDUSTRY.LEAF_MAT or not INDUSTRY.MAT_SHADES.has(extra):
			return fail("請靠近葉片地墊，選擇新的顏色。")
		var mat:Dictionary=state.ground[key(station_anchor(state.ground,p))]
		if mat.owner!=token:return fail("只有地墊主人可以換色。")
		if extra=="light":mat.erase("leaf_mat_shade")
		else:mat.leaf_mat_shade=extra
		return ok("葉片地墊換成了"+INDUSTRY.MAT_SHADES[extra]+"。")
	# C08: craft / workshop upgrade resolve either end of a wide workbench to its anchor (and
	# measure reach to both cells). A legacy 1x1 bench keeps the clicked cell and its own reach.
	if not removing_roof and not removing_mat and action in ["remove","move_object","start_processing","claim_processing","queue_processing","cancel_processing","cancel_processing_job","toggle_auto_processing","feed_processing","unload_processing_input","collect_processing_output",MATERIAL_SOURCES.PREPARE_ACTION,"dye_furniture","assemble","craft","upgrade_workshop",STONE_WORKSHOP.ACTION,"cook","claim_cook","cancel_cook","queue_cook","cancel_queued_cook",PUBLIC_KITCHEN.REGISTER,PUBLIC_KITCHEN.CONTRIBUTE]:
		p=station_anchor(state.objects,p)
		k=key(p)
		var station:Dictionary=state.objects.get(k,{})
		if INDUSTRY.square_part(station)==0:
			for offset:Vector2i in INDUSTRY.station_cells(station.type,INDUSTRY.is_vertical(station)):
				dist=minf(dist,Vector2(player.x,player.y).distance_to(Vector2(p+offset)+Vector2(0.5,0.5)))
	if not removing_roof and not removing_mat and action in ["remove","move_object",RESIDENT_GOALS.INSCRIBE_ACTION]:
		p=master_bench_anchor(state.objects,p)
		k=key(p)
	if action==RESIDENT_GOALS.TREE_NOTE_ACTION:
		if _region!=REGIONS.HOME or p!=Festival.TREE_CELL or dist>3.2 or not RESIDENT_GOALS.done(player,"lingpopo").has(4):
			return fail("完成鈴婆婆的最後一段故事後，才能到風鈴樹下留言。")
		var message:=ISLAND_NOTES.clean(extra)
		if message.is_empty():return fail("請輸入有效留言。")
		var notes:Array=state.get(RESIDENT_GOALS.TREE_NOTES,[])
		notes.push_front({"sender":str(player.name),"text":message,"time":float(state.time)})
		if notes.size()>ISLAND_NOTES.LIMIT:notes.pop_back()
		state[RESIDENT_GOALS.TREE_NOTES]=notes
		return ok("留言綁在風鈴樹的低枝上了。")
	if action==RESIDENT_GOALS.FESTIVAL_BELL_RING:
		var bell:Dictionary=state.objects.get(k,{})
		if dist>3.2 or not extra.is_empty() or bell.get("type") not in RESIDENT_GOALS.FESTIVAL_BELL_KINDS:
			return fail("請靠近風鈴節紀念鐘再敲響。")
		if float(state.time)-float(bell.get("bell_at",-5.0))<1.5:return fail("等鐘聲停了再敲一下。")
		bell.bell_at=float(state.time)
		if bell.type==RESIDENT_GOALS.CERAMIC_CHIME:return ok("叮——簷下陶風鈴響了一聲。")
		if bell.type==RESIDENT_GOALS.SHELL_CHIME:return ok("叮——潮紋貝殼輕輕碰了一聲。")
		return ok("叮——紀念鐘輕響了一聲。")
	if action==RESIDENT_GOALS.GARDEN_ACTION:
		if _region!=REGIONS.LANYANG or p!=LANYANG_LIFE.SERVICE or dist>3.2:return fail("請到蘭陽水圳旁找星禾。")
		return _shared_garden_choose(token,player,extra)
	if action==RESIDENT_GOALS.VOYAGE_ACTION:
		if extra not in ["return","photo"] and dist>3.2:return fail("請靠近碼頭的阿潮。")
		return _achao_voyage(token,player,p,extra)
	if action==FOREST_MUSHROOM.ACTION:return _forest_mushroom_action(player,p,dist,extra)
	if action=="outlying_deliver":
		var commission:Dictionary=OUTLYING_COMMISSIONS.DEFS.get(extra,{})
		if not TRANSIT.boat_open(state):return fail("請先完成碼頭與小船工程。")
		if commission.get("region","")!=_region or p!=TRANSIT.STATIONS.get(_region,{}).get("cell") or dist>3.2:
			return fail("請到委託所在的接駁站交件。")
		var delivery:=OUTLYING_COMMISSIONS.complete(state,token,extra,{"apply":true,"auth":token})
		return ok(delivery.text) if delivery.ok else fail(delivery.text)
	if action in ["dock_project_start","dock_repair"]:
		if _region!=REGIONS.HOME or p!=Vector2i(40,29) or dist>3.2:return fail("請到渡口公告板交付造船材料。")
		if not CHAPTER_ONE.phase(state)=="complete" or not state.get("flower_nursery",{}).get("garden",{}).get("complete",false):
			return fail("先完成渡口與田尾的公共故事。")
		var stage:=int(state.get("dock_stage",0))
		if stage>=DOCK_REPAIRS.size():return fail("碼頭和小船都已修復。")
		if action=="dock_project_start":
			if stage>0 or state.get("dock_project_started",false):return fail("碼頭與小船工程已經開工。")
			if not extra.is_empty():return fail("無效的工程申請。")
			state.dock_project_started=true
			return ok("碼頭與小船工程已開工！所有島民都可以交付材料。")
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
		var arrival := safe_transit_arrival(spawn,token)
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
		return ok(REGIONS.arrival_notice(destination))
	if action == "rescue":
		var point := safe_transit_arrival(REGIONS.spawn(_region) if _region != REGIONS.HOME else SPAWN,token)
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
	if action==SPRING_GARDEN.ACTION:
		return SPRING_GARDEN.apply(state,token,p,extra,_region==REGIONS.HOME)
	if action==SEA_BREEZE_FAIR.ACTION:
		return SEA_BREEZE_FAIR.apply(state,token,p,extra,_region==REGIONS.HOME)
	if action==AUTUMN_FEAST.ACTION:
		return AUTUMN_FEAST.apply(state,token,p,extra,_region==REGIONS.HOME)
	if action==LANTERN_STROLL.ACTION:
		return LANTERN_STROLL.apply(state,token,p,extra,_region==REGIONS.HOME,active_tokens,_stroll_route)
	if action==WARM_LANTERN_NIGHT.ACTION:
		return WARM_LANTERN_NIGHT.apply(state,token,p,extra,_region==REGIONS.HOME)
	if action==BEACH_TREASURE.ACTION:
		return BEACH_TREASURE.apply(state,token,p,extra,_region==REGIONS.HOME)
	if action==LOST_CHICKS.ACTION:
		var chase:=LOST_CHICKS.apply(state,token,p,extra,_region==REGIONS.HOME,active_tokens,_activity_can_step)
		return ok(str(chase.text)) if chase.ok else fail(str(chase.text))
	if action==COOKING_RELAY.ACTION:
		return COOKING_RELAY.apply(state,token,p,extra,_region==REGIONS.HOME,active_tokens)
	# C12 D14 夏季市集試吃：同一個渡口市集攤位，只寫本人的 player.summer_market（不碰 player.market）。
	if action in [SUMMER_MARKET.ACTION,SUMMER_MARKET.BUY_ROOTS]:
		if not MARKET.unlocked(state):return fail(SUMMER_MARKET.LOCKED)
		if _region!=REGIONS.HOME:return fail(SUMMER_MARKET.WRONG_REGION)
		var summer_stall:=MARKET.cell_for(state)
		if summer_stall==MARKET.NO_CELL:return fail(MARKET.NO_STALL)
		if p!=summer_stall:return fail(SUMMER_MARKET.WRONG_CELL)
		if dist>3.2:return fail(SUMMER_MARKET.TOO_FAR)
		if action==SUMMER_MARKET.BUY_ROOTS:
			if not extra.is_empty():return fail("請在夏季市集選擇根菜組。")
			return SUMMER_MARKET.buy_roots(state,token)
		return SUMMER_MARKET.apply(state,token,extra,NAMES)
	if action=="market_decor":
		if not MARKET.unlocked(state):return fail(MARKET.LOCKED)
		if _region!=REGIONS.HOME:return fail(MARKET.WRONG_REGION)
		var stall:=MARKET.cell_for(state)
		if stall==MARKET.NO_CELL:return fail(MARKET.NO_STALL)
		if p!=stall:return fail(MARKET.WRONG_CELL)
		if dist>3.2:return fail(MARKET.TOO_FAR)
		return MARKET_DECOR.change(player,extra,RESIDENT_GOALS.done(player,"xiaoli").has(3))
	# T071 市集攤位：家園廣場的個人攤位，只寫本人的 player.market。
	if action in MARKET.ACTIONS:
		if not MARKET.unlocked(state):return fail(MARKET.LOCKED)
		if _region!=REGIONS.HOME:return fail(MARKET.WRONG_REGION)
		var counter:Dictionary=state.objects.get(k,{})
		var cart:Dictionary={}
		if counter.get("type")==INDUSTRY.COAST_CART:
			cart=state.objects[key(station_anchor(state.objects,p))]
			if cart.owner!=token:return fail("只有攤車的主人能管理上架和營收。")
		elif counter.get("type")!=INDUSTRY.COAST_REGISTER:
			var stall:=MARKET.cell_for(state)
			if stall==MARKET.NO_CELL:return fail(MARKET.NO_STALL)
			if p!=stall:return fail(MARKET.WRONG_CELL)
		if dist>3.2:return fail(MARKET.TOO_FAR)
		var result:=MARKET.apply(state,token,action,extra,NAMES)
		if result.ok and action=="market_open" and not cart.is_empty():cart.market_cart_open=true
		return result
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
		var result:=TABLE_WARMER.apply(state,token,action,p,extra,_region==REGIONS.HOME)
		if result.ok and action==TABLE_WARMER.SERVE_ACTION:
			note_resident_participation(token,RESIDENT_GOALS.SHARED_MEAL_EVENT)
			MILU_SUPPER.record_serve(state.players[token],TABLE_WARMER.HOTPOT_ITEM)
		return result
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
	# T066 N03-4「最後一趟空車」：只寫本人的 player.bobo_empty_cart_stage；波波的站位與在場由這裡算給規則。
	if action in BOBO_EMPTY_CART.ACTIONS:
		return BOBO_EMPTY_CART.apply(state,token,action,p,extra,_region,bond_place(state,BOBO_EMPTY_CART.RESIDENT),RESIDENT_BOND.present(state,BOBO_EMPTY_CART.RESIDENT))
	# 第 40 章金瓜石初訪「運礦路線」：只寫本人的 state.ore_route.players[token] 與卸礦時的鈴幣。
	if action in ORE_ROUTE.ACTIONS:
		if BOBO_EMPTY_CART.person_active(player):return fail(BOBO_EMPTY_CART.ORE_BLOCKED) # 只擋本人推故事礦車的期間
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
	if action in Rabbit.ACTIONS or action in Cat.ACTIONS or action in Dog.ACTIONS or action in Fox.ACTIONS:
		if not extra.is_empty():return fail("請重新選擇寵物操作。")
		if action in Fox.ACTIONS:return _fox_action(player,action,p,dist)
		var species=Dog if action in Dog.ACTIONS else (Cat if action in Cat.ACTIONS else Rabbit)
		var adoption_site:Vector2i=LIVESTOCK.ANIMALS.sheep.cell
		if species==Cat:adoption_site=Cat.site(state)
		if species==Dog:adoption_site=Dog.SITE
		var at_site:bool=_region==REGIONS.HOME and state.picnic and p==adoption_site and dist<=3.2
		return Rabbit.act(self,player,action.get_slice("_",1),at_site,species.FIELD,species.NAME)
	if action in Hedgehog.ACTIONS:
		if _region!=REGIONS.HOME or p!=Hedgehog.site(state) or dist>3.2 or not extra.is_empty():
			return fail("請走到花宅庭院的刺蝟食盤旁。")
		return Hedgehog.act(self,player,action)
	if action in Squirrel.ACTIONS:
		if _region!=REGIONS.HOME or p!=Squirrel.SITE or dist>3.2 or not extra.is_empty():return fail("請走到望安西側林邊找橡果松鼠。")
		return Squirrel.act(self,player,action)
	if action==Seal.ACTION:
		if _region!=REGIONS.HOME or p!=Seal.SITE or dist>3.2 or not extra.is_empty():
			return fail("請走到望安南岸觀察胖海豹。")
		if not Seal.present(float(state.time)):return fail("現在漲潮，退潮時再來看看。")
		if player.get("seal_seen",false):return fail("這次相遇已經記下了，還可以和牠合照。")
		player.seal_seen=true
		return ok("胖海豹翻了個身，抬頭看向岸邊。可以打開海豹卡和牠合照了。")
	if action==Deer.ACTION:
		var site:=Deer.site(state)
		if _region==REGIONS.HOME and state.get("festival_story_open",false) and site==Deer.NO_SITE:
			return fail("風鈴樹旁擠滿了，留一塊空地給風鈴鹿歇腳。")
		if _region!=REGIONS.HOME or p!=site or dist>3.2 or not extra.is_empty():
			return fail("請到渡口風鈴樹旁。")
		if not state.get("festival_story_open",false):return fail("等風鈴節開幕後，再到樹下看看。")
		if player.get("windbell_deer_seen",false):return fail("這次相遇已經收進風鈴節回憶。")
		player.windbell_deer_seen=true
		return ok("風鈴鹿垂下頭，角間傳來輕輕一聲鈴響。")
	if _region in TRANSIT.LOCAL:return fail("公共站場只供步行與轉乘，請回農地或礦區作業。")
	var tea_farming:=_region==REGIONS.Bamboo.REGION and REGIONS.Bamboo.TEA_BEDS.has_point(p) and action in ["hoe","seed","water","harvest"]
	if _region==REGIONS.Bamboo.REGION and p in REGIONS.Bamboo.CLUMPS and action in ["axe","pick"]:
		if dist>3.2:return fail("請走近竹叢再採集。")
		if action!="axe" or not extra.is_empty():return fail("拿斧頭就能採收竹材。")
		if not REGIONS.Bamboo.ready(state,p):return fail("竹叢正在長新枝，過一會兒再來。")
		if not _drop_gather_items(token,k,{REGIONS.Bamboo.ITEM:REGIONS.Bamboo.YIELD}):return fail("先撿起地上的竹材，再採收這叢。")
		REGIONS.Bamboo.cut(state,p)
		player.gathering_points=mini(1000000000,int(player.get("gathering_points",0))+1)
		return {"ok":true,"message":"竹材落在地上了，走近就能撿起。","gather_dropped":true}
	if action==RESIDENT_GOALS.COURIER_CAP_ACTION:
		if extra not in ["wear","remove"] or p!=Vector2i(floori(player.x),floori(player.y)):return fail("請重新打開個人回憶冊換帽。")
		if not RESIDENT_GOALS.done(player,"luoluo").has(4):return fail("完成洛洛的未來信故事後可戴。")
		if extra=="remove":
			player.erase(RESIDENT_GOALS.COURIER_CAP_KEY)
			return ok("已脫下洛洛的信差帽。")
		player.erase(RESIDENT_GOALS.WOOL_HAT_KEY)
		player[RESIDENT_GOALS.COURIER_CAP_KEY]=true
		return ok("已戴上洛洛的信差帽。")
	var spring_bench:bool=_region==WARM_SPRINGS.REGION and WARM_SPRINGS.BENCH_CLEARING.has_point(p) and (
		(action=="build" and extra==RESIDENT_GOALS.STONE_BENCH) or
		(action in ["remove","move_object"] and state.objects.get(k,{}).get("type")==RESIDENT_GOALS.STONE_BENCH))
	if _region in REGIONS.ANGLING_RESERVES and not tea_farming and not spring_bench and action not in ["fish_start","fish_catch"] and action not in RESIDENT_BOND.ACTIONS and action not in RESIDENT_GOALS.ACTIONS and action not in [RESIDENT_GOALS.GUEST_CLOTH_ACTION,RESIDENT_GOALS.INN_CLEAR_ACTION,REGIONS.Springs.REST_REPLAY,WARM_SPRINGS.REST_JOIN,WARM_SPRINGS.BATH_ACTION,WARM_SPRINGS.CRACK_ACTION,WARM_SPRINGS.INN_PORTAL,WARM_SPRINGS.INN_USE,RESIDENT_GOALS.PAINT_INVITE_ACTION,RESIDENT_GOALS.POSTCARD_CLUE_ACTION,RESIDENT_GOALS.DIANDIAN_SEAT_ACTION]: # T066：居民互動不是施工。
		return fail("保護區可以垂釣，施工請回家園。")
	if _region == FLOWER_NURSERY.REGION and action in FLOWER_REJECTED:return fail(FLOWER_REJECT_MSG)
	if _region == SALT_PAN.REGION and not _salt_allowed(action,p,extra):return fail(SALT_PAN.REJECT_MESSAGE)
	if dist>(5.0 if action=="build_area" and crafting_level(player)>=BATCH_BUILD_LEVEL else 3.2): return fail("靠近一點，才能和它互動")
	if action=="floor_placement_access":
		var floor_piece:Dictionary=state.ground.get(k,{})
		if _region!=REGIONS.HOME or not ROOM_ENCLOSURE.is_floor_kind(floor_piece.get("type")) or floor_piece.get("owner")!=token:
			return fail("只有家園地板的主人可以更改放置權限。")
		if extra not in PLOT_PERMISSIONS.FLOOR_ACCESS:return fail("無效的放置權限。")
		if extra=="legacy":floor_piece.erase("placement_access")
		else:floor_piece.placement_access=extra
		return ok("地板放置權限已更新。")
	if action=="room_visit_access":
		var room_floor:Dictionary=state.ground.get(k,{})
		if _region!=REGIONS.HOME or not ROOM_ENCLOSURE.is_floor_kind(room_floor.get("type")) or room_floor.get("owner")!=token:
			return fail("請在自己的家園地板上設定參觀權限。")
		var guest_token:=""
		if extra.begins_with("friend:"):
			guest_token=_regional_guest(token,extra.trim_prefix("friend:"))
			if guest_token.is_empty():return fail("請選擇同區在線的玩家。")
		elif extra not in ["owner","island"]:return fail("無效的參觀權限。")
		var room:=ROOM_ENCLOSURE.analyze(state,p)
		if extra!="island":
			var problem:=visit_restriction_problem(token,room)
			if not problem.is_empty():return fail(problem)
		var affected:Array=room.cells if not room.cells.is_empty() else [p]
		for spot:Vector2i in affected:
			var piece:Dictionary=state.ground[key(spot)]
			if piece.owner!=token:continue
			if extra!="island":piece.owner_visit=true
			else:piece.erase("owner_visit")
			if guest_token.is_empty():piece.erase("visit_guest")
			else:piece.visit_guest=guest_token
		var place:="房間" if room.sealed else "戶外地塊"
		if not guest_token.is_empty():return ok(place+"已開放屋主與指定島民進入。")
		return ok(place+("改為僅屋主可進入。" if extra=="owner" else "已開放同島玩家參觀。"))
	if action=="furniture_remove_access":
		var furniture:Dictionary=state.objects.get(k,{})
		if _region!=REGIONS.HOME or furniture.get("owner")!=token or furniture.get("type") not in PLOT_PERMISSIONS.SHARED_REMOVAL_FURNITURE or furniture.get("aru_public",false):
			return fail("只有物主可以更改家園家具的拆除權限。")
		if extra not in ["owner","island"]:return fail("無效的拆除權限。")
		if extra=="island":furniture.guest_remove=true
		else:furniture.erase("guest_remove")
		return ok("家具拆除權限已更新。")
	if action in TEA_SERVICE.HOUSE_ACTIONS:return TEA_SERVICE.apply_house(state,token,action,p,extra,_region)
	if action in TEA_REVISIT.HOUSE_ACTIONS:
		if action==TEA_REVISIT.HOUSE_RECLAIM and _region==TEA_CERAMICS.MAOKONG and p==TEA_REVISIT.HOUSE_SITE \
			and TEA_SERVICE.portions(state,TEA_REVISIT.HOUSE_KEY)>0:
			return fail("壺裡還有熱茶，留給晚點到的島民吧。")
		return TEA_REVISIT.house_action(state,token,action,p,extra,_region)
	if action in [RESIDENT_GOALS.ARU_PARK_PLACE,RESIDENT_GOALS.ARU_PARK_PHOTO]:
		if _region!=REGIONS.HOME or RESIDENT_BOND.stage(player,"aru")<4:
			return fail("和阿榆成為好友後，才能布置渡口公共長椅。")
		if action==RESIDENT_GOALS.ARU_PARK_PHOTO:
			if p!=RESIDENT_GOALS.ARU_PARK_VIEW or not extra.is_empty() or dist>=3.2:
				return fail("請到公共長椅地塊的拍照位置。")
			for kind:String in RESIDENT_GOALS.ARU_PARK_SLOTS:
				if not RESIDENT_GOALS.aru_park_has(state.objects,kind):return fail("請先在公共地塊放好長椅和木燈。")
			player[RESIDENT_GOALS.ARU_PHOTO_KEY]=true
			return ok("阿榆可以在島民手冊裡看見這次的布置紀錄。")
		if RESIDENT_GOALS.ARU_PARK_SLOTS.get(extra)!=p or water(p):
			return fail("請將長椅或木燈放在它的公共預留位置。")
		var placed:=_build_piece(token,p,extra)
		if placed.ok:state.objects[k].aru_public=true
		return placed
	if action in [RESIDENT_GOALS.ARU_REST_ACTION,RESIDENT_GOALS.ARU_REST_LEAVE]:
		return _aru_bench_action(token,player,p,action,extra)
	if action==INDUSTRY.VINE_COLOR_ACTION:
		var arch:Dictionary=state.objects.get(key(station_anchor(state.objects,p)),{})
		if dist>3.2 or arch.get("type")!=INDUSTRY.VINE_ARCH or arch.get("owner")!=token:
			return fail("只能靠近自己的藤蔓花門換花色。")
		if not INDUSTRY.VINE_COLORS.has(extra):return fail("請選擇花門提供的花色。")
		if extra=="pink":arch.erase("vine_color")
		else:arch.vine_color=extra
		return ok("藤蔓花門換成了%s。"%INDUSTRY.VINE_COLORS[extra])
	if action in [INDUSTRY.POT_RACK_PUT,INDUSTRY.POT_RACK_TAKE]:
		if dist>3.2:return fail("請靠近銅框花架。")
		return _copper_rack_action(token,p,action,extra)
	if action in NURSERY_BOX.ACTIONS:
		if dist>3.2:return fail("請靠近溫室育苗箱。")
		return _nursery_action(token,player,p,action,extra)
	if action in [POSTCARDS.PUT,POSTCARDS.TAKE]:
		var rack:Dictionary=state.objects.get(k,{})
		if rack.get("type")!=POSTCARDS.RACK or rack.get("owner")!=token:return fail("只能整理自己的海風明信片架。")
		var shown:Array=rack.get(POSTCARDS.SLOTS,[])
		if action==POSTCARDS.PUT:
			if extra not in POSTCARDS.earned(player):return fail("先到這個地方旅行，就能收藏它的明信片。")
			if extra in shown:return fail("這張明信片已經在架上。")
			if shown.size()>=POSTCARDS.CAPACITY:return fail("請先收起一張明信片。")
			shown.append(extra)
			rack[POSTCARDS.SLOTS]=shown
			return ok("已擺上「"+POSTCARDS.CARDS[extra]+"」。")
		if extra not in shown:return fail("這張明信片沒有展示。")
		shown.erase(extra)
		if shown.is_empty():rack.erase(POSTCARDS.SLOTS)
		return ok("明信片已收回旅行收藏。")
	if action==OAR_SIGN.ACTION:
		var sign:Dictionary=state.objects.get(k,{})
		if sign.get("type")!=OAR_SIGN.KIND or sign.get("owner")!=token:return fail("只有路標的主人能變更目的地。")
		if extra.is_empty():
			sign.erase(OAR_SIGN.FIELD)
			return ok("已收起這面木槳路標的方向標記。")
		var destination:=OAR_SIGN.cell(extra)
		if destination==OAR_SIGN.NO_CELL or not is_land(destination) or water(destination):
			return fail("請選擇這張地圖上的陸地。")
		sign[OAR_SIGN.FIELD]=key(destination)
		return ok("木槳路標已指向「%s」。"%OAR_SIGN.direction_name(p,destination))
	if action in [INDUSTRY.COUNTER_PUT,INDUSTRY.COUNTER_TAKE]:
		var counter:Dictionary=state.objects.get(key(station_anchor(state.objects,p)),{})
		if dist>3.2 or counter.get("type")!=INDUSTRY.COAST_FISH_COUNTER or counter.get("owner")!=token:
			return fail("只能靠近自己的冰藍魚貨台整理展示。")
		if not FISH.has(extra):return fail("請選擇可展示的漁獲。")
		if action==INDUSTRY.COUNTER_PUT:
			if counter.items.has(extra):return fail("這種漁獲已經在展示台上。")
			if counter.items.size()>=INDUSTRY.COUNTER_CAPACITY:return fail("三個展示位都已放滿。")
			if int(inv.get(extra,0))<1:return fail("背包裡沒有這種漁獲。")
			give(inv,extra,-1)
			counter.items[extra]=1
			return ok("已展示"+FISH[extra].name+"。")
		if not counter.items.has(extra):return fail("展示台上沒有這種漁獲。")
		if not ITEM_CATALOG.can_hold(extra,int(inv.get(extra,0))+1):return fail("背包已滿，漁獲仍留在展示台。")
		give(inv,extra,1)
		counter.items.erase(extra)
		return ok("取回"+FISH[extra].name+"。")
	if action in [INDUSTRY.TEA_CABINET_PUT,INDUSTRY.TEA_CABINET_TAKE]:
		var cabinet:Dictionary=state.objects.get(key(station_anchor(state.objects,p)),{})
		if dist>3.2 or cabinet.get("type")!=INDUSTRY.TEA_DISPLAY_CABINET or cabinet.get("owner")!=token or INDUSTRY.square_part(cabinet)!=0:
			return fail("只能靠近自己的茶葉展示櫃整理展示。")
		if extra not in INDUSTRY.TEA_CABINET_TEAS:return fail("請選擇可展示的茶葉。")
		var shown:Dictionary=cabinet.items
		if action==INDUSTRY.TEA_CABINET_PUT:
			if INDUSTRY.tea_cabinet_total(shown)>=INDUSTRY.TEA_CABINET_SLOTS:return fail("三個展示位都已放滿。")
			if int(inv.get(extra,0))<1:return fail("背包裡沒有這種茶葉。")
			give(inv,extra,-1)
			shown[extra]=int(shown.get(extra,0))+1
			return ok("已展示"+NAMES[extra]+"。")
		if int(shown.get(extra,0))<1:return fail("展示櫃上沒有這種茶葉。")
		if not ITEM_CATALOG.can_hold(extra,int(inv.get(extra,0))+1):return fail("背包已滿，茶葉仍留在展示櫃。")
		give(inv,extra,1)
		if int(shown[extra])<=1:shown.erase(extra)
		else:shown[extra]=int(shown[extra])-1
		return ok("取回"+NAMES[extra]+"。")
	if action in [INDUSTRY.SNACK_PUT,INDUSTRY.SNACK_TAKE]:
		return _tea_snack_shelf_action(token,player,p,dist,action,extra)
	if action in [INDUSTRY.AQUARIUM_STOCK,INDUSTRY.AQUARIUM_TAKE]:
		var aquarium:Dictionary=state.objects.get(key(station_anchor(state.objects,p)),{})
		if dist>3.2 or not extra.is_empty() or aquarium.get("type")!=INDUSTRY.AQUARIUM or aquarium.get("owner")!=token:
			return fail("只能靠近自己的魚缸照料紅尾小鯉。")
		var fish:=INDUSTRY.AQUARIUM_FISH
		var held:=int(inv.get(fish,0))
		if action==INDUSTRY.AQUARIUM_STOCK:
			if not aquarium.items.is_empty():return fail("魚缸已經有一尾魚。")
			if held<1:return fail("背包裡沒有紅尾小鯉。")
			give(inv,fish,-1)
			aquarium.items[fish]=1
			return ok("放進一尾紅尾小鯉，牠就在水裡游了起來。")
		if not aquarium.items.has(fish):return fail("魚缸裡沒有小鯉。")
		if not ITEM_CATALOG.can_hold(fish,held+1):return fail("背包中的物品已達上限。")
		give(inv,fish,1)
		aquarium.items.erase(fish)
		return ok("紅尾小鯉已取回背包。")
	if action in [INDUSTRY.SEED_DISPLAY,INDUSTRY.SEED_CLEAR]:
		var cabinet:Dictionary=state.objects.get(key(station_anchor(state.objects,p)),{})
		if dist>3.2 or cabinet.get("type")!=INDUSTRY.SEED_CABINET or cabinet.get("owner")!=token:
			return fail("只能靠近自己的種子標本櫃整理展示。")
		if not CROPS.has(extra) or not player.collection.crops.has(extra):
			return fail("先在菜園圖鑑登錄這種作物。")
		var samples:Array=cabinet.get(INDUSTRY.SEED_SAMPLES,[])
		if action==INDUSTRY.SEED_DISPLAY:
			if extra in samples:return fail("櫃上已有這一種標本。")
			if samples.size()>=INDUSTRY.SEED_SAMPLE_SLOTS:return fail("三個展示位都滿了。")
			samples.append(extra)
		else:
			if extra not in samples:return fail("櫃上沒有這一種標本。")
			samples.erase(extra)
		if samples.is_empty():cabinet.erase(INDUSTRY.SEED_SAMPLES)
		else:cabinet[INDUSTRY.SEED_SAMPLES]=samples
		return ok("放上了%s的種子標本。"%CROPS[extra].name if action==INDUSTRY.SEED_DISPLAY else "收起了%s的種子標本。"%CROPS[extra].name)
	if action in ["inn_luggage_place","inn_luggage_take"]:
		var display:Dictionary=state.objects.get(key(station_anchor(state.objects,p)),{})
		if display.get("type")!=INDUSTRY.LUGGAGE_RACK or display.get("owner")!=token or not ITEM_CATALOG.is_known(extra):
			return fail("只能在自己的旅人行李架整理展示品。")
		var items:Dictionary=display.items
		var held:=int(inv.get(extra,0))
		var shown:=int(items.get(extra,0))
		if action=="inn_luggage_place":
			if luggage_count(items)>=INDUSTRY.LUGGAGE_SLOTS:return fail("兩個展示位已滿。")
			if held<1:return fail("背包沒有這項物品。")
			give(inv,extra,-1)
			give(items,extra,1)
			return ok("已放上一件展示品。")
		if shown<1:return fail("架上沒有這項展示品。")
		if not ITEM_CATALOG.can_hold(extra,held+1):return fail("背包中的物品已達上限。")
		give(inv,extra,1)
		if shown==1:items.erase(extra)
		else:give(items,extra,-1)
		return ok("已取回一件展示品。")
	if action in ["inn_tea_place","inn_tea_take"]:
		var display:Dictionary=state.objects.get(k,{})
		var tea:=INN_TEA_ITEM if extra.is_empty() else extra
		if display.get("type")!=INN_TEA_TABLE or display.get("owner")!=token or tea not in INN_TEA_ITEMS:
			return fail("只能整理自己的暖薑茶小桌。")
		var cups:int=display.items.get(tea,0)
		if action=="inn_tea_place":
			if inn_tea_count(display.items)>=INN_TEA_SLOTS:return fail("兩個杯位都擺了茶。")
			if int(inv.get(tea,0))<1:return fail("背包裡沒有"+str(NAMES[tea])+"。")
			give(inv,tea,-1)
			give(display.items,tea,1)
			return ok("已把一杯茶擺到桌上。")
		if cups<1:return fail("桌上還沒有茶。")
		if int(inv.get(tea,0))>=1000000000:return fail("背包中的茶飲已達上限。")
		give(inv,tea,1)
		if cups==1:display.items.erase(tea)
		else:give(display.items,tea,-1)
		return ok("已收回一杯茶。")
	if action==WELCOME_SIGN.WRITE:
		var sign:Dictionary=state.objects.get(k,{})
		if sign.get("type") not in [WELCOME_SIGN.KIND,WALL_FIXTURES.HOME_SIGN] or sign.get("owner")!=token:
			return fail("只能編輯自己的門牌或迎賓牌。")
		var home_sign:bool=sign.type==WALL_FIXTURES.HOME_SIGN
		var lines:=WELCOME_SIGN.decode(extra)
		if lines.is_empty():return fail("請確認門牌標題與歡迎語的字數。" if home_sign else "請確認旅舍名稱與歡迎語的字數。")
		if lines==["","",""]:sign.erase("welcome")
		else:sign.welcome=lines
		return ok("手刻門牌已更新。" if home_sign else "迎賓牌已更新。")
	if action==RESIDENT_GOALS.INSCRIBE_ACTION:
		var piece:Dictionary=state.objects.get(k,{})
		if not RESIDENT_GOALS.INSCRIPTION_KINDS.has(piece.get("type")) or piece.get("owner")!=token:
			return fail("只能替自己的門牌或雙人長椅刻字。")
		if not RESIDENT_GOALS.done(player,"aru").has(3):
			return fail("先和阿榆完成〈留下新的刮痕〉。")
		var message:=extra.strip_edges()
		if not RESIDENT_GOALS.valid_inscription(extra) or not RESIDENT_GOALS.valid_inscription(message):
			return fail("刻字限 18 字，請刪除無法顯示的字元。")
		if message.is_empty():piece.erase("inscription")
		else:piece.inscription=message
		return ok("已擦去原本的刻字。" if message.is_empty() else "已把字刻在木頭上。")
	if action==RESIDENT_GOALS.SHEEP_STEP_ACTION:
		var sheep_cell:Vector2i=LIVESTOCK.ANIMALS.sheep.cell
		if _region!=REGIONS.HOME or not state.picnic or p!=sheep_cell or Vector2(player.x,player.y).distance_to(Vector2(sheep_cell)+Vector2(0.5,0.5))>3.2:
			return fail("請到渡口的雲朵羊飼料站旁。")
		if RESIDENT_BOND.stage(player,"mianmian")<4:return fail("和棉棉成為好友後，才能一起看小羊走出屋簷。")
		if not RESIDENT_GOALS.shelter_built(state):return fail("先替雲朵羊搭好遮雨棚。")
		if not extra in ["","calm"]:return fail("請重新打開飼料站。")
		if RESIDENT_GOALS.Weather.at(float(state.time),"home").raining and extra!="calm":return fail("下雨天牠不急著出來。晴天再來，或開啟減少動態。")
		if not preload("res://scripts/sheep_shelter.gd").new().route_clear(state):return fail("棚前有障礙，請留一格通道。")
		var watched:Variant=player.get(RESIDENT_GOALS.SHEEP_STEP_KEY)
		var finished:bool=RESIDENT_GOALS.done(player,"mianmian").has(4)
		if (watched is float or watched is int) and not finished:
			if float(state.time)-float(watched)<RESIDENT_GOALS.SHEEP_STEP_SECONDS:return fail("牠還在慢慢走，再等一下。")
			return ok("你已經看到小羊自己走出來了，回去告訴棉棉吧。")
		player[RESIDENT_GOALS.SHEEP_STEP_KEY]=float(state.time)
		return ok("你站在一旁，沒有出聲。")
	if action in [RESIDENT_GOALS.SHEEP_SHELTER_ACTION,RESIDENT_GOALS.SHEEP_TOY_ACTION]:
		if _region!=REGIONS.HOME or not state.picnic or p!=LIVESTOCK.ANIMALS.sheep.cell:
			return fail("請到渡口的雲朵羊飼料站。")
		if action==RESIDENT_GOALS.SHEEP_TOY_ACTION:
			if not RESIDENT_GOALS.done(player,"mianmian").has(2) or not RESIDENT_GOALS.SHEEP_TOYS.has(extra):
				return fail("先替雲朵羊布置好角落，再向棉棉領玩具。")
			if float(state.time)-float(state.get(RESIDENT_GOALS.SHEEP_PLAY_KEY,{}).get("at",-10.0))<RESIDENT_GOALS.SHEEP_PLAY_SECONDS:
				return fail("雲朵羊還在玩，等牠歇一下。")
			state[RESIDENT_GOALS.SHEEP_PLAY_KEY]={"toy":extra,"at":float(state.time)}
			return ok("雲朵羊好奇地湊近了%s。"%RESIDENT_GOALS.SHEEP_TOYS[extra])
		if RESIDENT_BOND.stage(player,"mianmian")<2:return fail("先和棉棉熟悉，才能幫忙搭棚。")
		var part:Dictionary=RESIDENT_GOALS.SHEEP_COMFORT_PARTS.get(extra,{})
		if part.is_empty():return fail("找不到這項布置。")
		var progress:=int(player.get(RESIDENT_GOALS.SHEEP_SHELTER_KEY,0))
		if (progress&int(part.bit))!=0:return fail("你已經完成了這項布置。")
		for material:String in part.cost:
			if int(inv.get(material,0))<int(part.cost[material]):return fail("還需要%s %d。"%[NAMES[material],part.cost[material]])
		for material:String in part.cost:give(inv,material,-int(part.cost[material]))
		player[RESIDENT_GOALS.SHEEP_SHELTER_KEY]=progress|int(part.bit)
		return ok("已%s。"%part.label)
	if action==RESIDENT_GOALS.DIANDIAN_SEAT_ACTION:
		if not extra.is_empty() or _region!=RESIDENT_BOND.GARDEN_REGION or p!=RESIDENT_BOND.GARDEN_CELL:
			return fail("請到星芽庭園的映星池邊找點點。")
		if RESIDENT_BOND.stage(player,"diandian")<2 or not RESIDENT_GOALS.done(player,"diandian").has(1):
			return fail("先回報三張速寫，再和點點坐一會兒。")
		if RESIDENT_GOALS.done(player,"diandian").has(2):return fail("已完成這張速寫，可以在手帳重看。")
		var occupied:Array=[]
		for other:String in active_tokens:
			if other==token:continue
			var visitor:Dictionary=state.players.get(other,{})
			if visitor.get("region")==_region and visitor.get(RESIDENT_GOALS.DIANDIAN_SEAT_KEY,false):
				occupied.append(Vector2i(floori(visitor.x),floori(visitor.y)))
		for site:Vector2i in RESIDENT_GOALS.DIANDIAN_SEATS:
			var feet:=Vector2(site)+Vector2(0.5,0.5)
			if site in occupied or not can_stand(feet):continue
			player.erase("fishing")
			player[RESIDENT_GOALS.DIANDIAN_SEAT_KEY]=true
			player.x=feet.x
			player.y=feet.y
			return ok("你在池邊坐下了，挑個喜歡的手勢給點點看。")
		return fail("池邊的位置都有人坐，等一會兒再來。")
	if action==RESIDENT_GOALS.TEA_CHAIR_ACTION:
		var seat:Dictionary=RESIDENT_GOALS.TEA_CHAIRS.get(extra,{})
		if _region!=TEA_CERAMICS.MAOKONG or seat.is_empty() or p!=seat.cell:
			return fail("請到貓空茶亭旁的預留座位。")
		if RESIDENT_BOND.stage(player,"chacha")<4:return fail("和茶茶成為好友後，可以替來客留個座位。")
		if player.has(RESIDENT_GOALS.TEA_CHAIR_KEY):return fail("你已經替茶亭留了一張椅子。")
		player[RESIDENT_GOALS.TEA_CHAIR_KEY]=extra
		return ok("你替來客留了一張%s，回去找茶茶吧。"%seat.name)
	if action==RESIDENT_GOALS.TEA_SETUP_ACTION:
		if _region!=TEA_CERAMICS.MAOKONG or p!=TEA_CERAMICS.TEA_NPC:
			return fail("請在貓空茶屋和茶茶一起擺桌。")
		if RESIDENT_BOND.stage(player,"chacha")<1:return fail("先和茶茶打個招呼。")
		if player.has(RESIDENT_GOALS.TEA_SETUP_KEY):return fail("這席茶已經擺好了。")
		var arrangement:=extra.split(":")
		if arrangement.size()!=2 or arrangement[0] not in RESIDENT_GOALS.TEA_AXES or arrangement[1]!="2":
			return fail("選好方向，把兩只杯子放上桌。")
		player[RESIDENT_GOALS.TEA_SETUP_KEY]=arrangement[0]
		return ok("茶桌和兩只杯子擺好了，找茶茶說一聲吧。")
	if action in [RESIDENT_GOALS.MURAL_HANG_ACTION,RESIDENT_GOALS.MURAL_SIGN_ACTION]:
		if _region!=REGIONS.HOME or p!=RESIDENT_GOALS.MURAL_SITE or not extra.is_empty() or not state.picnic:
			return fail("請到風鈴渡口的公告板展區。")
		var mural:Dictionary=state.get(RESIDENT_GOALS.MURAL_KEY,{})
		if action==RESIDENT_GOALS.MURAL_HANG_ACTION:
			if not mural.is_empty():return fail("展區已掛上合畫，歡迎在空白處落款。")
			if RESIDENT_BOND.stage(player,"diandian")<4 or not RESIDENT_GOALS.done(player,"diandian").has(3):
				return fail("先完成點點的第一幅合畫，並和她成為好友。")
			var subjects:Array=player.get(RESIDENT_GOALS.PAINT_INVITES_KEY,[])
			if subjects.size()!=RESIDENT_GOALS.PAINT_INVITE_COUNT:return fail("請先邀齊三位居民。")
			state[RESIDENT_GOALS.MURAL_KEY]={"subjects":subjects.duplicate(),"author":token,"author_name":str(player.name).left(12),"signatures":{}}
			return ok("你把合畫掛上了。旁邊還留著下一個位置。")
		if mural.is_empty():return fail("要等合畫掛上後才能加入。")
		if RESIDENT_GOALS.mural_contributed(state,token):return fail("畫上已經留著你的名字。")
		mural.signatures[token]=str(player.name).left(12)
		return ok("你在合畫留了一個身影和落款。")
	if action==RESIDENT_GOALS.PAINT_INVITE_ACTION:
		if RESIDENT_BOND.stage(player,"diandian")<3:return fail("先和點點建立信任，再幫她邀居民入畫。")
		var painting_goals:=RESIDENT_GOALS.done(player,"diandian")
		if not painting_goals.has(2) and not painting_goals.has(3):return fail("先到映星池邊完成點點的〈沒畫好的手〉。")
		if extra=="diandian" or extra not in RESIDENT_BOND.RESIDENTS or not RESIDENT_BOND.present(state,extra):
			return fail("請邀請點點以外、已在島上活動的居民。")
		var model_spot:=bond_place(state,extra)
		if _region!=str(model_spot[0]) or p!=model_spot[1]:return fail("到居民身邊才能提出邀請。")
		var invited:Array=player.get(RESIDENT_GOALS.PAINT_INVITES_KEY,[])
		if extra in invited:return fail("已經邀過這位居民了。")
		if invited.size()>=RESIDENT_GOALS.PAINT_INVITE_COUNT:return fail("三個位置都有人了，回去找點點吧。")
		invited.append(extra)
		player[RESIDENT_GOALS.PAINT_INVITES_KEY]=invited
		return ok("%s答應入畫。已記下 %d／%d 位居民。"%[RESIDENT_BOND.name_of(extra),invited.size(),RESIDENT_GOALS.PAINT_INVITE_COUNT])
	if action==RESIDENT_GOALS.GROWTH_ACTION:
		if _region not in RESIDENT_GOALS.GROWTH_REGIONS or not extra.is_empty() or RESIDENT_BOND.stage(player,"xinghe")<1:
			return fail("認識星禾後，可以在渡口或蘭陽記錄自己的作物。")
		var sample:Dictionary=state.crops.get(k,{})
		var kind:=str(sample.get("kind",""))
		if sample.get("owner","")!=token or sample.get("other_sown",false) or not CROPS.has(kind):return fail("請觀察自己種下的作物。")
		var logbook:Dictionary=player.get(RESIDENT_GOALS.GROWTH_LOG_KEY,{})
		if logbook.has(kind):return fail("已經收錄過這種作物。")
		if not logbook.is_empty() and not RESIDENT_GOALS.done(player,"xinghe").has(1):return fail("先把第一份紀錄帶去找星禾。")
		var tracked:Dictionary=player.get(RESIDENT_GOALS.GROWTH_KEY,{})
		var current:={"region":_region,"tile":k,"kind":kind}
		match RESIDENT_GOALS.growth_phase(sample,float(CROPS[kind].time)):
			"early":
				if tracked==current:return fail("幼苗已經記下了，等同一株成熟再來。")
				player[RESIDENT_GOALS.GROWTH_KEY]=current
				return ok("記下了%s的幼苗，等它成熟後再來。"%NAMES[kind])
			"mature":
				if tracked!=current:return fail("先記下這一株的幼苗階段。")
				logbook[kind]=true
				player[RESIDENT_GOALS.GROWTH_LOG_KEY]=logbook
				player.erase(RESIDENT_GOALS.GROWTH_KEY)
				return ok("記下了%s成熟時的樣子。"%NAMES[kind])
			_:return fail("作物正在長大，等成熟再來。")
	if action==RESIDENT_GOALS.ADDRESS_ACTION:
		if _region!=REGIONS.HOME or not RESIDENT_BOND.present(state,"luoluo") or RESIDENT_BOND.stage(player,"luoluo")<1:
			return fail("先在渡口和洛洛打個招呼。")
		var address_stage:=RESIDENT_GOALS.address_progress(player)
		if extra=="take":
			if p!=RESIDENT_BOND.post_cell(state) or address_stage!=0:return fail("請在洛洛身邊領取待送的信。")
			player[RESIDENT_GOALS.ADDRESS_KEY]=RESIDENT_GOALS.ADDRESS_CARRIED
			return ok("你收下了洛洛的信，可以打開信封查看線索。")
		if extra not in RESIDENT_GOALS.ADDRESS_CANDIDATES or p!=Village.resident_cell(state,extra):
			return fail("要走到收件人身邊才能送信。")
		if address_stage!=RESIDENT_GOALS.ADDRESS_CARRIED:return fail("目前沒有待送的信。")
		if extra!=RESIDENT_GOALS.ADDRESS_RECIPIENT:return fail("%s說這封不是自己的，信仍由你保管。"%RESIDENT_BOND.name_of(extra))
		player[RESIDENT_GOALS.ADDRESS_KEY]=RESIDENT_GOALS.ADDRESS_DELIVERED
		return ok("阿榆收下了信，回去告訴洛洛吧。")
	if action==RESIDENT_GOALS.POSTCARD_CLUE_ACTION:
		if RESIDENT_BOND.stage(player,"luoluo")<2 or RESIDENT_GOALS.done(player,"luoluo").has(2):
			return fail("先找洛洛了解這封沒有地址的信。")
		if not RESIDENT_GOALS.done(player,"luoluo").has(1):
			return fail("先和洛洛完成〈寫得太小的地址〉。")
		if not RESIDENT_GOALS.POSTCARD_CLUES.has(extra) or RESIDENT_BOND.stage(player,extra)<1 or not RESIDENT_BOND.present(state,extra):
			return fail("請向已認識的居民詢問。")
		var place:=bond_place(state,extra)
		if _region!=place[0] or p!=place[1]:return fail("走到這位居民身邊才能詢問。")
		var clues:=RESIDENT_GOALS.postcard_clues(player)
		if extra in clues:return fail("這位居民的線索已收進手冊。")
		if clues.size()>=RESIDENT_GOALS.KNOWN_NEEDED:return fail("已集齊三條線索，回去找洛洛吧。")
		clues.append(extra)
		player[RESIDENT_GOALS.POSTCARD_CLUES_KEY]=clues
		return ok("%s的線索已收進手冊（%d／%d）。"%[RESIDENT_BOND.name_of(extra),clues.size(),RESIDENT_GOALS.KNOWN_NEEDED])
	if action==RESIDENT_GOALS.GUEST_ROOM_ACTION:
		if _region!=REGIONS.HOME or p!=Vector2i(floori(player.x),floori(player.y)) or not extra.is_empty():
			return fail("站到家園的客房內再登記。")
		if RESIDENT_BOND.stage(player,"nuannuan")<3:return fail("先和暖暖建立信任。")
		if player.get(RESIDENT_GOALS.GUEST_ROOM_KEY,false) or RESIDENT_GOALS.done(player,"nuannuan").has(3):return fail("客房已經記在手帳裡。")
		const Rooms=preload("res://scripts/house_rooms.gd")
		var guest:=Rooms.guest_room(state,Rooms.inspect(state,p),p,token)
		if not guest.ready:return fail("需要一間完整的客房，裡面有床、燈、椅，至少一件由你擺放。")
		player[RESIDENT_GOALS.GUEST_ROOM_KEY]=true
		return ok("已記下客房的布置，回礁溪找暖暖。")
	if action==WANGAN_MEMORY.ACTION:
		if _region!=REGIONS.HOME or (p!=WANGAN_MEMORY.SITE and (p!=WANGAN_MEMORY.COURT_SIGN or not WANGAN_MEMORY.courtyard_available(state))):
			return fail("請到風鈴渡口的花宅觀察牌。")
		return WANGAN_MEMORY.record(player,extra)
	if action==WANGAN_MEMORY.WEIR_ACTION:
		if _region!=REGIONS.HOME or p not in WANGAN_MEMORY.WEIR_SITES:return fail("請靠近風鈴渡口或南岸的石滬觀察點。")
		return WANGAN_MEMORY.observe_tide(player,extra,WANGAN_COAST.high_tide(float(state.time)))
	if action==WANGAN_MEMORY.LOG_ACTION:
		if _region!=REGIONS.HOME or p!=RESIDENT_BOND.dock_cell(state) or not extra.is_empty():
			return fail("請到風鈴渡口找阿潮。")
		if not RESIDENT_BOND.present(state,"achao"):return fail(RESIDENT_BOND.DOCK_LOCKED)
		return WANGAN_MEMORY.finish_log(player)
	if action==TEA_HOUSE_INTERIOR.PORTAL:
		if _region!=TEA_HOUSE_INTERIOR.REGION or not extra.is_empty():return fail("請走到貓空茶屋的門口。")
		var tea_inside:=TEA_HOUSE_INTERIOR.inside(player)
		var tea_doorway:=TEA_HOUSE_INTERIOR.EXIT if tea_inside else TEA_HOUSE_INTERIOR.DOOR
		if p!=tea_doorway:return fail("請走到貓空茶屋的門口。" if not tea_inside else "請走到茶屋的出口。")
		if not tea_inside and not TEA_REVISIT.house_open(state):return fail("貓空茶屋還沒開張。")
		if dist>TEA_HOUSE_INTERIOR.PORTAL_REACH:return fail("再靠近一點，才能出入茶屋。")
		var tea_cell:=TEA_HOUSE_INTERIOR.DOOR if tea_inside else TEA_HOUSE_INTERIOR.EXIT+Vector2i.UP
		var tea_to:=Vector2(tea_cell)+Vector2(0.5,0.5)
		if not can_stand(tea_to):
			tea_to=safe_arrival(tea_to,token)
			if tea_to==Vector2.ZERO:return fail("門口暫時擠不進去，稍後再試。")
		player.erase(TEA_HOUSE_INTERIOR.SEAT_KEY)
		player.erase("fishing")
		player.x=tea_to.x
		player.y=tea_to.y
		return ok("走出貓空茶屋。" if tea_inside else "走進貓空茶屋。")
	if action==POTTERY_WORKSHOP_INTERIOR.PORTAL:
		if _region!=POTTERY_WORKSHOP_INTERIOR.REGION or not extra.is_empty():return fail("請走到鶯歌合作陶坊的門口。")
		var pot_inside:=POTTERY_WORKSHOP_INTERIOR.inside(player)
		var pot_doorway:=POTTERY_WORKSHOP_INTERIOR.EXIT if pot_inside else POTTERY_WORKSHOP_INTERIOR.DOOR
		if p!=pot_doorway:return fail("請走到鶯歌合作陶坊的門口。" if not pot_inside else "請走到陶坊的出口。")
		if Vector2(float(player.x),float(player.y)).distance_to(POTTERY_WORKSHOP_INTERIOR.center(pot_doorway))>POTTERY_WORKSHOP_INTERIOR.REACH:return fail("再靠近一點，才能出入陶坊。")
		var pot_cell:=POTTERY_WORKSHOP_INTERIOR.DOOR if pot_inside else POTTERY_WORKSHOP_INTERIOR.EXIT+Vector2i.UP
		var pot_to:=POTTERY_WORKSHOP_INTERIOR.center(pot_cell)
		if not can_stand(pot_to):
			pot_to=safe_arrival(pot_to,token)
			if pot_to==Vector2.ZERO:return fail("門口暫時擠不進去，稍後再試。")
		player.erase("fishing")
		player.x=pot_to.x
		player.y=pot_to.y
		return ok("走出鶯歌合作陶坊。" if pot_inside else "走進鶯歌合作陶坊。")
	if action==TEA_HOUSE_INTERIOR.SIT:
		if _region!=TEA_HOUSE_INTERIOR.REGION or not TEA_HOUSE_INTERIOR.inside(player) or not extra.is_empty():
			return fail("請走進貓空茶屋再入座。")
		if not TEA_HOUSE_INTERIOR.SEAT_FEET.has(p):return fail("這裡沒有可坐的椅子。")
		var tea_seat:=TEA_HOUSE_INTERIOR.seat_key(p)
		if dist>TEA_HOUSE_INTERIOR.SEAT_REACH:return fail("再靠近一點，才能坐下。")
		var tea_feet:=TEA_HOUSE_INTERIOR.feet_position(p)
		if str(player.get(TEA_HOUSE_INTERIOR.SEAT_KEY,""))==tea_seat and Vector2(float(player.x),float(player.y)).distance_to(tea_feet)<=TEA_HOUSE_INTERIOR.SEAT_STAY:
			return ok("正在椅子上休息。移動即可起身。")
		var tea_guests:={}
		for other:String in active_tokens:
			if other!=token and state.players.has(other) and str(state.players[other].get("region",REGIONS.HOME))==TEA_HOUSE_INTERIOR.REGION:
				tea_guests[other]=state.players[other]
		if TEA_HOUSE_INTERIOR.occupied(tea_guests,tea_seat,token):return fail("這張椅子有人坐了。")
		player.erase("fishing")
		player.erase(RESIDENT_GOALS.MASTER_BENCH_SEAT)
		player.erase(RESIDENT_GOALS.DIANDIAN_SEAT_KEY)
		player.erase(REGIONS.Springs.REST_SEAT_KEY)
		player[TEA_HOUSE_INTERIOR.SEAT_KEY]=tea_seat
		player.x=tea_feet.x
		player.y=tea_feet.y
		return ok("在茶屋坐下來喝茶。移動即可起身。")
	if action==WARM_SPRINGS.INN_USE:
		if _region!=WARM_SPRINGS.REGION or not WARM_SPRINGS.in_inn(player) or not extra.is_empty():
			return fail("請走進暖泉旅舍再使用房內家具。")
		var kind:String=WARM_SPRINGS.INN_FURNITURE.get(p,"")
		if kind==INDUSTRY.INN_BED:
			MEAL_BUFF.refill(player)
			return ok("在旅舍的厚被裡休息了一下，體力已恢復。")
		if kind!="chair":return fail("這件旅舍家具沒有可用的座位。")
		var seat_key:="%s:%s"%[WARM_SPRINGS.INN_USE,key(p)]
		for other:String in active_tokens:
			var visitor:Dictionary=state.players.get(other,{})
			if other!=token and visitor.get("region")==WARM_SPRINGS.REGION and visitor.get(WARM_SPRINGS.REST_SEAT_KEY)==seat_key:
				return fail("這張椅子有人坐了。")
		var feet:Vector2i=WARM_SPRINGS.INN_CHAIR_FEET[p]
		player[WARM_SPRINGS.REST_SEAT_KEY]=seat_key
		player.x=feet.x+0.5
		player.y=feet.y+0.5
		return ok("坐下來休息。移動即可起身。")
	if action==WARM_SPRINGS.INN_PORTAL:
		if _region!=WARM_SPRINGS.REGION or not extra.is_empty():return fail("請走到暖泉旅舍的門口。")
		var inside:=WARM_SPRINGS.in_inn(player)
		var doorway:=WARM_SPRINGS.INN_EXIT if inside else WARM_SPRINGS.INN_DOOR
		if p!=doorway:return fail("請走到暖泉旅舍的門口。")
		var destination:=WARM_SPRINGS.INN_DOOR if inside else WARM_SPRINGS.INN_EXIT+Vector2i.UP
		player.erase(WARM_SPRINGS.REST_SEAT_KEY)
		player.erase("fishing")
		player.x=destination.x+0.5
		player.y=destination.y+0.5
		return ok("回到暖泉溪畔。" if inside else "走進暖泉旅舍。")
	if action==WARM_SPRINGS.CRACK_ACTION:
		var index:=WARM_SPRINGS.CRACK_SITES.find(p)
		if _region!=WARM_SPRINGS.REGION or index<0 or dist>WARM_SPRINGS.CRACK_REACH or not extra.is_empty():
			return fail("靠近礁溪泡腳池的裂縫，就能在石緣留記號。")
		if RESIDENT_BOND.stage(player,"nuannuan")<2:return fail("先認識暖暖，和她聊聊池邊的裂縫。")
		if RESIDENT_GOALS.done(player,"nuannuan").has(2):return fail("你已經和暖暖修好池邊的裂縫。")
		var mask:=int(player.get(WARM_SPRINGS.CRACK_KEY,0))
		if WARM_SPRINGS.crack_marked(mask,index):return fail("這一道已經記下了。")
		mask|=1<<index
		player[WARM_SPRINGS.CRACK_KEY]=mask
		if mask==WARM_SPRINGS.CRACK_MASK:return ok("三處都記好了。帶陶土 8 和石材 12 回去找暖暖。")
		return ok("記下了%s。"%WARM_SPRINGS.CRACK_NAMES[index])
	if action==WARM_SPRINGS.BATH_ACTION:
		if _region!=WARM_SPRINGS.REGION or p!=WARM_SPRINGS.BATH_ENTRANCE or not extra.is_empty():return fail("請靠近礁溪的公共泡腳池。")
		if not state.get(WARM_SPRINGS.BATH_KEY,false):return fail("泡腳池還有裂縫。找暖暖一起修好它。")
		if player.get(WARM_SPRINGS.REST_SEAT_KEY)==WARM_SPRINGS.BATH_ACTION:return ok("正在泡腳。移動即可起身。")
		var occupied:=[]
		for other:String in active_tokens:
			var visitor:Dictionary=state.players.get(other,{})
			if visitor.get("region")==WARM_SPRINGS.REGION and visitor.get(WARM_SPRINGS.REST_SEAT_KEY)==WARM_SPRINGS.BATH_ACTION:
				occupied.append(Vector2(visitor.x,visitor.y))
		for offset:Vector2 in WARM_SPRINGS.BATH_SEATS:
			var place:=Vector2(WARM_SPRINGS.BATH_ORIGIN)+offset
			if place in occupied:continue
			player[WARM_SPRINGS.REST_SEAT_KEY]=WARM_SPRINGS.BATH_ACTION
			player.x=place.x
			player.y=place.y
			return ok("坐在公共池邊泡泡腳。移動即可起身。")
		return fail("公共泡腳池已坐滿，稍等一會兒吧。")
	if action==REGIONS.Springs.REST_JOIN:return _rest_join(player,token,p,extra)
	if action==REGIONS.Springs.REST_REPLAY:
		if _region!=REGIONS.Springs.REGION or p!=RESIDENT_BOND.SPRING_CELL or not extra.is_empty():
			return fail("請到礁溪找暖暖。")
		var choice:=str(RESIDENT_GOALS.done(player,"nuannuan").get(4,""))
		if not REGIONS.Springs.REST_SEATS.has(choice):return fail("先完成〈第一位住下的主人〉。")
		if _rest_seat_taken(token,choice):return fail("這個位子有人坐了。")
		_sit_at_inn(player,choice)
		return ok("又和暖暖坐了一會兒。移動即可起身。")
	if action==RESIDENT_GOALS.INN_CLEAR_ACTION:
		if _region!=RESIDENT_BOND.SPRING_REGION or p not in [RESIDENT_BOND.SPRING_CELL,WARM_SPRINGS.INN_DOOR] or not extra.is_empty():
			return fail("請到礁溪旅舍門口。")
		if RESIDENT_BOND.stage(player,"nuannuan")<1:return fail("先和暖暖打聲招呼。")
		if player.get(RESIDENT_GOALS.INN_CLEAR_KEY,false) or RESIDENT_GOALS.done(player,"nuannuan").has(1):
			return fail("旅舍門口已經清理好了。")
		player[RESIDENT_GOALS.INN_CLEAR_KEY]=true
		return ok("你掃開門邊的落葉，整理好門牌下的碎石。回去和暖暖一起點燈吧。")
	if action==RESIDENT_GOALS.GUEST_CLOTH_ACTION:
		var warm_spot:=bond_place(state,"nuannuan")
		if _region!=str(warm_spot[0]) or p!=warm_spot[1] or not extra.is_empty():return fail("請到暖暖身邊領旅舍布料。")
		if not RESIDENT_GOALS.done(player,"nuannuan").has(3):return fail("先向暖暖回報客房的布置。")
		if player.get(RESIDENT_GOALS.GUEST_CLOTH_KEY,false):return fail("旅舍布料已經領過了。")
		if int(inv.get("cotton_cloth",0))>999999998:return fail("布料已達背包上限，整理後再來領。")
		give(inv,"cotton_cloth",2)
		player[RESIDENT_GOALS.GUEST_CLOTH_KEY]=true
		return ok("暖暖把兩塊旅舍布料放進了你的背包。")
	if action==RESIDENT_GOALS.BELL_INSPECT_ACTION:
		if _region!=REGIONS.HOME or not RESIDENT_BOND.present(state,"lingpopo") or RESIDENT_BOND.stage(player,"lingpopo")<1:
			return fail("先到渡口和鈴婆婆說聲你好。")
		var clue_bit:=0
		var clue:=""
		if extra=="tree" and p==Festival.TREE_CELL:
			clue_bit=RESIDENT_GOALS.BELL_TREE_BIT
			clue="粗枝上有一截空繩，繩結還留著。"
		elif extra=="bell" and p==RESIDENT_BOND.bell_cell(state):
			clue_bit=RESIDENT_GOALS.BELL_CRACK_BIT
			clue="鈴口裂了一道，細繩還和樹上的一樣。"
		else:return fail("請靠近風鈴樹，或到鈴婆婆身邊查看小鈴。")
		var inspected:=int(player.get(RESIDENT_GOALS.BELL_INSPECT_KEY,0))
		if (inspected&clue_bit)!=0:return fail("這處線索已經記下了。")
		player[RESIDENT_GOALS.BELL_INSPECT_KEY]=inspected|clue_bit
		return ok(clue)
	if action==RESIDENT_GOALS.REST_KIT_ACTION:
		if _region!=MINES.IDS[0] or p!=MINES.REST or not RESIDENT_GOALS.REST_KIT_PARTS.has(extra):
			return fail("請到合作礦場第一層的提燈休息站。")
		if not state.picnic or RESIDENT_BOND.stage(player,"bobo")<3:return fail("先和波波建立信任，再幫他整備休息站。")
		var part:Dictionary=RESIDENT_GOALS.REST_KIT_PARTS[extra]
		var installed:=int(player.get(RESIDENT_GOALS.REST_KIT_KEY,0))
		var bit:=int(part.bit)
		if (installed&bit)!=0:return fail("你已經替休息站備好這一項了。")
		for material:String in part.cost:
			if int(inv.get(material,0))<int(part.cost[material]):return fail("%s還缺%s。"%[part.label,NAMES[material]])
		for material:String in part.cost:give(inv,material,-int(part.cost[material]))
		player[RESIDENT_GOALS.REST_KIT_KEY]=installed|bit
		return ok("你替休息站備好了%s。"%part.label)
	if action==RESIDENT_GOALS.RECIPE_PAGE_ACTION:
		if _region!=REGIONS.HOME or not RESIDENT_GOALS.RECIPE_PAGES.has(extra) or p!=milu_recipe_cell(state,extra):
			return fail("請到手記標出的地方找紙角。")
		if RESIDENT_BOND.stage(player,"milu")<2 or not RESIDENT_BOND.present(state,"milu"):
			return fail("先和米露熟悉，再幫她找食譜紙角。")
		var page:Dictionary=RESIDENT_GOALS.RECIPE_PAGES[extra]
		var found:=int(player.get(RESIDENT_GOALS.RECIPE_PAGE_KEY,0))
		if (found&int(page.bit))!=0:return fail("這片食譜紙角已經收好了。")
		player[RESIDENT_GOALS.RECIPE_PAGE_KEY]=found|int(page.bit)
		return ok("在%s找到一片食譜紙角。"%page.name)
	if action==RESIDENT_GOALS.ROUTE_ACTION:
		if _region!=REGIONS.HOME or not RESIDENT_GOALS.ROUTE_SIGNS.has(extra) or p!=achao_route_cell(extra):
			return fail("請走到渡口對應的路標。")
		if RESIDENT_BOND.stage(player,"achao")<2 or not RESIDENT_BOND.present(state,"achao"):
			return fail("先和阿潮熟悉，再替他記錄航線。")
		var flag:int=RESIDENT_GOALS.ROUTE_SIGNS[extra].bit
		var marks:=int(player.get(RESIDENT_GOALS.ROUTE_KEY,0))
		if (marks&flag)!=0:return fail("這座路標的方向已經記下了。")
		player[RESIDENT_GOALS.ROUTE_KEY]=marks|flag
		return ok("記下了%s的方向。"%RESIDENT_GOALS.ROUTE_SIGNS[extra].name)
	if action==RESIDENT_GOALS.SKETCH_ACTION:
		if _region!=REGIONS.HOME:return fail("請在渡口觀察作物或動物。")
		if RESIDENT_BOND.stage(player,"diandian")<1:return fail("先去星芽庭園和點點說聲你好。")
		var kind:String=state.crops.get(k,{}).get("kind","")
		var subject:String
		if extra.is_empty():
			if not CROPS.has(kind):return fail("這裡還沒有可記錄的作物。")
			subject=CROPS[kind].name
		else:
			if not RESIDENT_GOALS.SKETCH_ANIMALS.has(extra):return fail("找不到這種動物。")
			var animal_cell:Vector2i=CHICKEN_CELL if extra=="chicken" else LIVESTOCK.ANIMALS[extra].cell
			if p!=animal_cell or (extra!="chicken" and not state.picnic):return fail("請到已開放的動物照料地點記錄。")
			if not LIVESTOCK.adopted(state.get("livestock",{}),extra):return fail(LIVESTOCK.NOT_ADOPTED_MESSAGE)
			kind=extra
			subject=RESIDENT_GOALS.SKETCH_ANIMALS[kind]
		var sketches:Dictionary=player.get(RESIDENT_GOALS.SKETCH_KEY,{})
		if sketches.has(kind):return fail("這種動物或作物已經畫進速寫了。")
		if sketches.size()>=RESIDENT_GOALS.SKETCH_TARGET:return fail("三種都畫好了，去找點點吧。")
		sketches[kind]=true
		player[RESIDENT_GOALS.SKETCH_KEY]=sketches
		return ok("畫下了%s（%d／%d）。"%[subject,sketches.size(),RESIDENT_GOALS.SKETCH_TARGET])
	if action in COMMUNITY.ACTIONS:
		if _region!=REGIONS.HOME or not state.picnic or p==COMMUNITY.NO_CELL or p!=COMMUNITY.table_cell(state) or not extra.is_empty() or dist>3.2:
			return fail("請到風鈴渡口的共餐桌分食。")
		var dish:=action.get_slice("_",1)
		var item:String=COMMUNITY.DISHES[dish]
		var serving:=COMMUNITY.share_dish(state,token,action,dish,NAMES[item])
		if serving.ok:
			if action.begins_with("claim_"):_record_discovery(player,"meals",item)
			else:
				note_resident_participation(token,RESIDENT_GOALS.SHARED_MEAL_EVENT)
				MILU_SUPPER.record_serve(player,item)
		return serving
	if action==MILU_SUPPER.ACTION:
		return MILU_SUPPER.apply(state,player,_region==REGIONS.HOME,p,dist,extra)
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
		return ok("謝謝你為渡口捐款。" if action=="fund_donate" else "公共基金已支付剩餘材料，公告板修好了！河灣橋要備齊木材、繩索與石工台橋基後才開通。")
	if action in ["livestock_adopt","livestock_feed","livestock_collect","livestock_pet","livestock_brush","livestock_install","livestock_empty","livestock_pen"]:
		if _region!=REGIONS.HOME or not state.picnic or not LIVESTOCK.ANIMALS.has(extra) or p!=LIVESTOCK.ANIMALS[extra].cell or dist>3.2:
			return fail("完成渡口野餐後，可照料牧場家畜。")
		if action=="livestock_adopt":
			# D07: one shared island record; the adopter pays the fee, later players see it adopted.
			var adoption:Dictionary=LIVESTOCK.adopt(state.livestock,extra,int(player.coins))
			if adoption.ok:player.coins=int(player.coins)-int(adoption.cost)
			return adoption
		if action=="livestock_install" and not state.get("flower_nursery",{}).get("garden",{}).get("complete",false):
			return fail("完成田尾公共花園後解鎖畜牧收集器。")
		if action=="livestock_pen" and not LIVESTOCK.pen_status(state.objects,extra):
			return fail("請先圍好圈舍並留一扇木門。")
		var care_result:Dictionary=LIVESTOCK.perform(state.livestock,inv,extra,action,float(state.time))
		if care_result.ok and extra=="cow" and action=="livestock_pet":state.livestock.cow[COW_CARE.FIELD]=token
		return care_result
	# T042 public kitchen: HOME only, after the normal 3.2 reach gate (p = stove).
	if action in PUBLIC_KITCHEN.ACTIONS:
		if _region!=REGIONS.HOME:return fail("請回到風鈴渡口使用公共廚房。")
		return PUBLIC_KITCHEN.perform(self,token,action,p,extra)
	# T036 explicit material sources. Plain recipe IDs never contain '|', so the
	# backpack-only actions below stay unchanged; perform() re-enters _apply
	# with the canonical action and the plain recipe ID (no recursion loop).
	if action in AnimalCollector.ACTIONS:
		if _region!=REGIONS.HOME:return fail("請回風鈴渡口使用收集器。")
		return AnimalCollector.act(self,token,p,action,extra)
	if action=="dye_furniture":return _dye_furniture(token,p,extra)
	if action=="upgrade_workshop":
		if state.objects.get(k,{}).get("type")!="bench":return fail("請在工作台完成工坊升級。")
		if crafting_level(player)<WORKSHOP_LEVEL:return fail("手作達到六級後可升級工坊。")
		if player.get("workshop_upgraded",false):return fail("你的工坊已升級。")
		player.workshop_upgraded=true
		return ok("工坊已升級，家園工坊開放裝配桌。")
	if action=="assemble":return _assemble(player,state.objects.get(k,{}),token,extra)
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
		var tea_p:=p
		# Indoor workshop: the requested indoor station (not the nearest one) must own this action and be in
		# reach; only then does its cell become the legacy outdoor cell, so record/stock/queue/cooldown are shared.
		if _region==POTTERY_WORKSHOP_INTERIOR.REGION and POTTERY_WORKSHOP_INTERIOR.inside(player) and POTTERY_WORKSHOP_INTERIOR.ACTION_STATIONS.has(action):
			var indoor:=POTTERY_WORKSHOP_INTERIOR.resolve(player,action,p)
			if not indoor.ok:return fail(str(indoor.message))
			tea_p=indoor.p
		return TEA_CERAMICS.apply(state,token,action,_region,tea_p,extra)
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
	if action in GUARDIAN.ACTIONS:return _guardian_action(token,action,p,extra)
	if action==GUARDIAN_TRIAL.KEY:return _guardian_trial_action(token,p,extra)
	# 害羞菇: interact actions, plus the ordinary watering can on exactly its B2 cell (before crop gates).
	if action in SHY.ACTIONS or (action==SHY.WATER_ACTION and p==SHY.MUSHROOM and shy_available()):return _shy_action(token,action,p,extra)
	if action==SHY_SPORES.ACTION:return _shy_spore_action(token,p,extra)
	if action in CRAB.ACTIONS or action==CRAB.SHELL_ACTION:return _crab_action(token,action,p,extra)
	if action in PORTER.ACTIONS:return _porter_action(token,action,p,extra)
	if action in MEADOW.ACTIONS:return _meadow_action(token,action,p,extra)
	if action==MEADOW_ADVENTURE.ACTION:return _meadow_adventure_action(token,p,extra)
	if action in ["mine_travel","mine_rest","mine_commission","mine_extract","mine_mud_lure","mine_mud_claim","mine_mud_duel",HOIST_ACTION] or (_region in MINES.IDS and action=="pick" and p in MINES.NODES):
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
		var depth:=MINES.depth_of(_region)
		var loan_site:=(_region==REGIONS.HOME and p==COPPER_CELL) or (_region==REGIONS.JINGUASHI and p==MINES.ENTRY)
		loan_site=loan_site or (depth in range(1,MINES.SHALLOW_DEPTH+1) and depth<=int(state.mine_depths.unlocked) and p==MINES.REST)
		if not loan_site:return fail("請到渡口礦料點、下坑路牌或已開通的淺層休息站借用公用鎬。")
		if not state.picnic:return fail("渡口野餐後才開放公用鎬。")
		if player.get("borrowed_mine_pick",false):return fail("你已有公用鎬使用資格。")
		player.borrowed_mine_pick=true
		return ok("取得公用鎬使用資格。可在渡口及金瓜石地表採銅，也可在礦道 B1–B5 採礦。")
	if _region == REGIONS.JINGUASHI and (action == "mine_copper" or (action == "pick" and p in JINGUASHI.NODES)):
		if p not in JINGUASHI.NODES:return fail("請到合作礦場的礦料點。")
		if active_mining_pick(inv).is_empty() and not player.get("borrowed_mine_pick",false):return fail("先製作強化鎬，或到渡口借用公用鎬。")
		var ready: Dictionary = state.jinguashi.ready
		if float(ready.get(k,0.0)) > float(state.time):return fail("這個礦點正在整理，請稍候。")
		if int(inv.get("copper_ore",0)) > 1000000000 - JINGUASHI.YIELD:return fail("背包中的銅礦料已達上限。")
		give(inv,"copper_ore",JINGUASHI.YIELD)
		ready[k] = float(state.time) + JINGUASHI.COOLDOWN
		return ok("取得合作礦場銅礦料 +%d。" % JINGUASHI.YIELD)
	if action==PUBLIC_TILLER.ACTION:
		# 只在渡口登記；資格旗標寫在本人身上，不發物品。距離已由上方的互動距離檢查把關。
		if _region!=REGIONS.HOME:return fail(PUBLIC_TILLER.WRONG_PLACE)
		var loan:Dictionary=PUBLIC_TILLER.borrow(state,player,_region,p)
		return ok(loan.message) if loan.ok else fail(loan.message)
	if _region != REGIONS.HOME and action in ["chapter_starter","ship","buy","sell","picnic","donate","pet","feed","egg","install_egg_basket","festival_start","festival_collect","quarry","mine_copper"]:
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
		var sale := SHIPPING.verify(extra, inv, SHIPPING.prices(CROPS, FISH, OTHER_SALES,true), int(player.coins))
		if not sale.ok:
			return sale
		for item in sale.quantities:
			inv[item] -= sale.quantities[item]
			_record_crop_sale(player,item)
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
		var gathered:=_harvest_batch(token,player,plan)
		if not gathered.ok:return gathered
		give(inv,"charcoal",-1)
		player.last_harvest={"at":float(state.time),"x":p.x,"y":p.y,"cells":plan.cells.duplicate()}
		return ok("收割 %d 格 · %s · 木炭 −1"%[plan.cells.size(),gathered.message])
	if action=="seed_area":
		if int(inv.get("seeder",0))<1:return fail("先在工作台製作手推播種機")
		if not CROPS.has(extra):return fail("請先選擇作物種子")
		if int(inv.get(extra+"_seed",0))<1:return fail("這種種子用完了，按 C 換種子或到攤位購買")
		if int(inv.get("charcoal",0))<1:return fail("播種機需要木炭，這次沒有消耗種子")
		if float(state.time)-float(player.get("last_seed",{}).get("at",-10))<SEEDER.COOLDOWN:return fail("播種機正在收起料斗，稍候再試")
		var plan:Dictionary=SEEDER.plan(self,token,p,extra)
		if plan.cells.is_empty():return fail("範圍內沒有自己的空農田，未消耗種子或木炭")
		_plant_planned_seeds(token,inv,plan.cells,extra)
		give(inv,"charcoal",-1)
		player.last_seed={"at":float(state.time),"x":p.x,"y":p.y,"cells":plan.cells.duplicate(),"kind":extra}
		return ok("播下%s %d 格 · 種子 −%d · 木炭 −1，記得供水"%[CROPS[extra].name,plan.cells.size(),plan.cells.size()])
	if action=="till_area":
		if not PUBLIC_TILLER.can_till(player):return fail(PUBLIC_TILLER.NEED_MACHINE)
		if int(inv.get("charcoal",0))<1:return fail("耕田機需要木炭，這次沒有施工")
		if float(state.time)-float(player.get("last_till",{}).get("at",-10))<TILLER.COOLDOWN:return fail("耕田機正在收起滾輪，稍候再試")
		var plan:Dictionary=TILLER.plan(self,token,p)
		if plan.cells.is_empty():return fail("範圍內沒有可整地的空地，未消耗木炭")
		_open_farm_soil(token,plan.cells)
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
	if action==STONE_WORKSHOP.ACTION:return _stone_craft(token,player,k,extra)
	if action==STONE_WORKSHOP.DONATE_ACTION:
		if _region!=REGIONS.HOME:return fail("請回到風鈴渡口使用這項功能。")
		return _bridge_donate(token,player,p,extra)
	if action=="craft":
		if extra=="supply_box_kit" and not supply_box_unlocked(player):return fail("探索達到六級，或完成波波的休息站事件後可製作便攜補給箱。")
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
		if active_mining_pick(inv).is_empty() and not player.get("borrowed_mine_pick",false):return fail("需要強化石鎬或公用鎬才能採銅")
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
		if parts.size()!=3 or parts[0] not in ["floor","stone_floor","path","spring_pebble_path"]+TERRACOTTA_ROOF.AREA_ROOFS or not parts[1].is_valid_int() or not parts[2].is_valid_int():return fail("請重新選擇施工範圍")
		var end:=Vector2i(int(parts[1]),int(parts[2]))
		var a:=Vector2i(mini(p.x,end.x),mini(p.y,end.y))
		var b:=Vector2i(maxi(p.x,end.x),maxi(p.y,end.y))
		var count:=(b.x-a.x+1)*(b.y-a.y+1)
		var area_limit:=build_area_limit(player)
		if abs(end.x)>1000 or abs(end.y)>1000 or count>area_limit or count<1:return fail("一次最多施工 %d 格"%area_limit)
		var reach:=5.0 if area_limit>BASIC_BUILD_AREA else 3.2
		var kind:String=parts[0]
		if kind in STONE_WORKSHOP.STATION_BUILDS and not STONE_WORKSHOP.has_station(home_layer("objects")):
			return fail(STONE_WORKSHOP.STATION_MSG)
		var keys:Array[String]=[]
		for y in range(a.y,b.y+1):
			for x in range(a.x,b.x+1):
				var tile:=Vector2i(x,y);var tile_key:=key(tile)
				if Vector2(player.x,player.y).distance_to(Vector2(tile)+Vector2(0.5,0.5))>reach:return fail("整個施工範圍需在可施工距離內")
				if water(tile) or protected(tile):return fail("範圍包含水域或公共通道，這次沒有扣料")
				if not allows_public_build(token,tile):return fail(PUBLIC_BUILD_DENIED)
				if kind=="roof":
					if state.roofs.has(tile_key) or not state.ground.has(tile_key) or not ROOM_ENCLOSURE.is_floor_piece(state.ground[tile_key]) or state.ground[tile_key].owner!=token:return fail("整片屋頂都需要自己的地板，且不能重疊屋頂")
				elif kind==TERRACOTTA_ROOF.KIND:
					if not ROOM_ENCLOSURE.is_floor_piece(state.ground.get(tile_key)) or state.ground[tile_key].owner!=token:return fail(TERRACOTTA_ROOF.MSG_AREA)
				elif resource(tile)!="" or state.crops.has(tile_key) or state.objects.has(tile_key) or state.ground.has(tile_key):return fail("範圍裡有東西，這次沒有放置或扣料")
				keys.append(tile_key)
		var retile:Dictionary={}
		if kind==TERRACOTTA_ROOF.KIND:
			var sites:=_terracotta_sites(token,keys,true,true)
			if not sites.ok:return fail(sites.message)
			retile=sites.refunds
		var recipe:Dictionary=BUILD[kind].duplicate()
		recipe.erase("name")
		for item in recipe:
			if int(inv.get(item,0))<int(recipe[item])*count:return fail("整片施工的"+NAMES[item]+"不足")
		for item in recipe:give(inv,item,-int(recipe[item])*count)
		_terracotta_refund(retile)
		var layer:Dictionary=state.roofs if kind in TERRACOTTA_ROOF.AREA_ROOFS else state.ground
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
		if not allows_public_build(token,destination):return fail(PUBLIC_BUILD_DENIED)
		var floor_permission:=PLOT_PERMISSIONS.placement_floor(self,token,destination)
		if not floor_permission.ok:return fail(floor_permission.message)
		var to_key:=key(destination)
		if _region==REGIONS.HOME and PUBLIC_KITCHEN.is_site_cell(state,p):return fail(PUBLIC_KITCHEN.MSG_LOCKED)
		var obj:Dictionary=state.objects.get(k,{})
		if obj.get("aru_public",false):return fail("已捐給公共地塊的家具會留給大家使用。")
		var permission:=PLOT_PERMISSIONS.can_dismantle(self,token,p,true)
		if not permission.ok:return fail(permission.message)
		if obj.type in ["wall","window","door"]:return fail("牆門窗請拆除後重新建造，材料會退回")
		if obj.type==INDUSTRY.COAST_CART and obj.get("market_cart_open",false):return fail(INDUSTRY.CART_BUSY)
		if obj.type==INDUSTRY.HOLLOW_BED and _seat_occupied(p):return fail(INDUSTRY.HOLLOW_BUSY)
		if obj.type in INDUSTRY.FOUR_SEAT_TABLES and _seat_occupied(p):return fail(INDUSTRY.MUSHROOM_TABLE_BUSY)
		if obj.type==INDUSTRY.MUSHROOM_STOOL and _seat_occupied(p):return fail(INDUSTRY.MUSHROOM_STOOL_BUSY)
		if obj.type==INDUSTRY.WOOD_CHAIR and _seat_occupied(p):return fail(INDUSTRY.WOOD_CHAIR_BUSY)
		if obj.type==INDUSTRY.INDIGO_CUSHION and _seat_occupied(p):return fail(INDUSTRY.INDIGO_CUSHION_BUSY)
		if obj.type==NURSERY_BOX.KIND and NURSERY_BOX.occupied(obj):return fail(NURSERY_BOX.BUSY_MESSAGE)
		if obj.type==INDUSTRY.BEACH_CHAIR and _seat_occupied(p):return fail(INDUSTRY.BEACH_BUSY)
		if obj.type==INDUSTRY.BAMBOO_LOUNGER:
			if obj.owner!=token:return fail(INDUSTRY.LOUNGER_NOT_OWNER)
			if _seat_occupied(station_anchor(state.objects,p)):return fail(INDUSTRY.LOUNGER_BUSY)
		if obj.type==INDUSTRY.SHELL_TABLE and _seat_occupied(p):return fail(INDUSTRY.SHELL_BUSY)
		if obj.type=="conveyor" and (obj.enabled or not obj.items.is_empty()):return fail("請停用並清空輸送帶")
		if obj.type=="mine_drill" and not MINE_DRILL.can_move(obj):return fail("請停用並清空採掘機。")
		if obj.type=="waterworks" and not WATERWORKS.can_move(obj):return fail("請停用並清空水力加工台。")
		if (obj.type in LOGISTICS.PROCESSORS or obj.type in INDUSTRY.MANUAL_STATIONS) and not LOGISTICS.processing_idle(obj):return fail(PROCESSING_MSG_BUSY)
		if obj.type in LOGISTICS.PROCESSORS and not LOGISTICS.processor_ready_to_move(obj):return fail("請停用自動加工並清空設備")
		if obj.type=="forester" and not FORESTRY.can_move(obj):return fail("請先停用林務站並取回全部材料")
		if obj.has("job"):return fail("先領取或取消目前工作，再搬動")
		if obj.has("cooking") and not cooking_idle(obj):return fail(COOKING_MSG_BUSY)
		if obj.type=="mine_drill" and MINE_DRILL.placement(destination)<0:return fail("採掘機必須正對本層指定礦點。")
		if destination==p:return fail("這就是原本的位置")
		# C13: never wall in a mill entrance by moving something solid onto the cell in front of it.
		var moved_front:=_mill_front_claim_problem(str(obj.type),destination,INDUSTRY.square_part(obj)==0,INDUSTRY.is_vertical(obj),p,INDUSTRY.mill_entrance_offset(INDUSTRY.mill_facing(obj)) if INDUSTRY.is_new_mill(obj) else Vector2i(-1000,-1000))
		if moved_front.is_empty() and obj.type in RESIDENT_GOALS.DOUBLE_BENCHES:
			moved_front=_mill_front_claim_problem(str(obj.type),destination+master_bench_offset(obj),false,false,p)
		if not moved_front.is_empty():return fail(moved_front)
		if obj.type in WALL_FIXTURES.KINDS and not WALL_FIXTURES.has_support(state.objects,destination,str(obj.owner),str(obj.type),state.edges):
			return fail(WALL_FIXTURES.support_message(str(obj.type)))
		if obj.type==WALL_FIXTURES.TOOL_BOARD and not WALL_FIXTURES.has_tool_board_support(state.objects,destination,token,state.edges):
			return fail(WALL_FIXTURES.TOOL_BOARD_SUPPORT)
		var hanging:bool=obj.type==ROOF_FIXTURES.HANGING_POT
		if hanging and not ROOF_FIXTURES.supported(state.roofs.get(to_key),str(obj.owner)):
			return fail(ROOF_FIXTURES.SUPPORT_MESSAGE)
		if obj.has("collector_animal"):return fail("先領取產物並取回收集籃，再搬移收集器。")
		if obj.type in RESIDENT_GOALS.DOUBLE_BENCHES:
			if obj.type in RESIDENT_GOALS.INDEPENDENT_TWO_SEATS and _seat_occupied(p):return fail(RESIDENT_GOALS.two_seat_busy(obj.type))
			if Vector2(player.x,player.y).distance_to(Vector2(destination)+Vector2(0.5,0.5))>3.2:return fail("新位置也要在身邊三格內")
			var available:=_footprint_space(token,destination,[Vector2i.ZERO,master_bench_offset(obj)],p)
			if not available.ok:return available
			_master_bench_clear(p)
			state.objects.erase(k)
			state.objects.erase(key(p+master_bench_offset(obj)))
			state.objects[to_key]=obj
			_master_bench_end(destination,obj)
			return ok("已搬好%s。"%BUILD[obj.type].name if obj.type in RESIDENT_GOALS.INDEPENDENT_TWO_SEATS else "搬好了！兩格長椅和刻字都留在一起。")
		if Vector2(player.x,player.y).distance_to(Vector2(destination)+Vector2(0.5,0.5))>3.2:return fail("新位置也要在身邊三格內")
		if INDUSTRY.square_part(obj)==0:
			var station_cells:=INDUSTRY.station_cells(obj.type,INDUSTRY.is_vertical(obj))
			if obj.type==INDUSTRY.IMPERFECT_TEA_PAVILION:
				var essential:=pavilion_site_problem(destination)
				if not essential.is_empty():return fail(essential)
			var available:=_footprint_space(token,destination,station_cells,p,obj.type!=WALL_FIXTURES.TOOL_BOARD and obj.type!=INDUSTRY.IMPERFECT_TEA_PAVILION and not INDUSTRY.is_new_mill(obj))
			if not available.ok:return available
			# C13: the facing travels with the mill; the new spot needs a walkable entrance front and no one in its solid cells.
			if INDUSTRY.is_new_mill(obj):
				var mill_problem:=_mill_site_problem(destination,INDUSTRY.mill_facing(obj),p)
				if not mill_problem.is_empty():return fail(mill_problem)
			if obj.type==INDUSTRY.RIVERSIDE_SCREEN and not INDUSTRY.is_folded_screen(obj) and _riverside_screen_occupied(destination,INDUSTRY.is_vertical(obj)):
				return fail(INDUSTRY.RIVERSIDE_OCCUPIED)
			if obj.type in [INDUSTRY.FOOT_BATH,INDUSTRY.BEACH_CHAIR,INDUSTRY.BAMBOO_LOUNGER,INDUSTRY.HOLLOW_BED]+INDUSTRY.FOUR_SEAT_TABLES:_master_bench_clear(p)
			for offset:Vector2i in station_cells:state.objects.erase(key(p+offset))
			state.objects[to_key]=obj
			_write_station_parts(destination,obj)
			if obj.type==INDUSTRY.CEDAR_BED and state.players[obj.owner].get(INDUSTRY.HOME_REST_FIELD)==k:
				state.players[obj.owner][INDUSTRY.HOME_REST_FIELD]=to_key
			return ok("已搬好"+BUILD[obj.type].name+"。")
		if obj.type==INDUSTRY.HEDGEHOG_BASKET and _region==REGIONS.HOME and Hedgehog.is_food_site(destination):
			return fail("請把午睡籃放在食盤旁的空地。")
		if obj.type=="water_pump" and not INDUSTRY.near_river(self,destination):return fail("水泵需放在河水兩格內的陸地")
		if water(destination) or protected(destination) or resource(destination)!="" or state.objects.has(to_key) or (state.crops.has(to_key) and not hanging):return fail("新位置不是可用空地，家具仍留在原處")
		if obj.type not in ["chair",INDUSTRY.INDIGO_CUSHION,"lamp",INDUSTRY.PAPER_TEA_LAMP,"sign","water_pipe","conveyor","diversion_gate",ROOF_FIXTURES.HANGING_POT,OAR_SIGN.KIND,INDUSTRY.HEDGEHOG_BASKET,WALL_FIXTURES.BARK_FRAME]:
			for active_token in regional_tokens():
				var who:Dictionary=state.players[active_token]
				if Vector2(who.x,who.y).distance_to(Vector2(destination)+Vector2(0.5,0.5))<0.8:return fail("這裡有人，等他移開再搬")
		if obj.type=="mine_drill":obj.dir=MINE_DRILL.placement(destination)
		if obj.type in [RESIDENT_GOALS.GARDEN_CHAIR,INDUSTRY.SHELL_TABLE,INDUSTRY.MUSHROOM_STOOL,INDUSTRY.WOOD_CHAIR,INDUSTRY.INDIGO_CUSHION]:_master_bench_clear(p)
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
	if action=="inn_bed_rest":
		var bed:Dictionary=state.objects.get(key(station_anchor(state.objects,p)),{})
		if _region!=REGIONS.HOME or bed.get("type")!=INDUSTRY.INN_BED or not extra.is_empty():
			return fail("請靠近家園裡的厚被旅舍床。")
		MEAL_BUFF.refill(player)
		return ok("在厚被裡休息了一下，體力已恢復。")
	if action=="inn_outfit":
		var wardrobe:Variant=state.objects.get(k,{}).get("type")
		if _region!=REGIONS.HOME or wardrobe not in RESIDENT_GOALS.WORKWEAR_WARDROBES or extra not in ["original","blue"]:
			return fail("請靠近家園裡可以換工作服的衣櫃。")
		var unlocked:=FLOWER_NURSERY.blue_outfit_unlocked(player)
		if not unlocked and (extra=="blue" or wardrobe!=RESIDENT_GOALS.FOREST_WARDROBE):
			return fail("先在田尾染製一套藍染工作服。")
		if unlocked:player.blue_outfit_unlocked=true
		if extra=="blue":player.blue_outfit=true
		else:player.erase("blue_outfit")
		return ok("已換上藍染工作服。" if extra=="blue" else "已換回原色工作服。")
	if action==RESIDENT_GOALS.WOOL_HAT_ACTION:
		if not RESIDENT_GOALS.wool_hat_unlocked(player):return fail("完成棉棉的「自己走出屋簷」後可戴。")
		if player.get(RESIDENT_GOALS.WOOL_HAT_KEY,false):
			player.erase(RESIDENT_GOALS.WOOL_HAT_KEY)
			return ok("已脫下羊毛帽。")
		player[RESIDENT_GOALS.WOOL_HAT_KEY]=true
		player.erase(RESIDENT_GOALS.COURIER_CAP_KEY)
		return ok("已戴上羊毛帽。")
	if action==RESIDENT_GOALS.APRON_ACTION:
		if _region!=REGIONS.HOME or (p!=bond_place(state,"milu")[1] and state.objects.get(k,{}).get("type") not in RESIDENT_GOALS.WARDROBES) or not extra.is_empty():
			return fail("請到米露身邊或家園的更衣櫃旁換圍裙。")
		if not RESIDENT_GOALS.apron_unlocked(player):return fail("完成米露的共餐事件後可穿戴。")
		if player.get(RESIDENT_GOALS.APRON_KEY,false):
			player.erase(RESIDENT_GOALS.APRON_KEY)
			return ok("已收起米露的圍裙。")
		player[RESIDENT_GOALS.APRON_KEY]=true
		return ok("已換上米露的圍裙。")
	if action in [XIAOLI_SHOP.SIGN_ACTION,XIAOLI_SHOP.SCALE_ACTION]:
		if _region!=REGIONS.HOME or p!=bond_place(state,"xiaoli")[1]:return fail("請到小栗的渡口小店。")
		if not RESIDENT_GOALS.done(player,"xiaoli").has(4):return fail("請先和小栗掛好招牌。")
		if action==XIAOLI_SHOP.SCALE_ACTION:
			if not extra.is_empty():return fail("請重新選擇紀念秤。")
			return XIAOLI_SHOP.claim_scale(player)
		if not XIAOLI_SHOP.valid_name(extra):return fail(XIAOLI_SHOP.BAD_NAME)
		player[XIAOLI_SHOP.NAME_KEY]=extra
		return ok("小栗掛上「%s」的招牌。"%XIAOLI_SHOP.shop_name(player,""))
	if action in RESIDENT_GOALS.ACTIONS:
		var goal_parts:=extra.split(":",true,3 if action==RESIDENT_GOALS.ACTION and extra.begins_with(RESIDENT_GOALS.FUTURE_PREFIX) else 0)
		var goal_resident:=str(goal_parts[0]) if goal_parts.size()>0 else ""
		if goal_resident not in RESIDENT_BOND.RESIDENTS:return fail("請走到這位居民身邊。")
		var goal_spot:=bond_place(state,goal_resident)
		if str(goal_spot[0])!=_region or p!=goal_spot[1]:return fail("請走到這位居民身邊。")
		var goal_locked:=RESIDENT_BOND.locked_reason(state,goal_resident)
		if not goal_locked.is_empty():return fail(goal_locked)
		Village.ensure_player(player)
		if action==RESIDENT_GOALS.CLAIM_ACTION:return RESIDENT_GOALS.claim(player,inv,goal_parts)
		# The seat is checked before apply() so a taken primary seat never consumes materials or rewards.
		if action==RESIDENT_GOALS.ACTION and goal_resident=="nuannuan" and goal_parts.size()==4 and str(goal_parts[1])=="4" \
			and REGIONS.Springs.REST_SEATS.has(str(goal_parts[2])) and not RESIDENT_GOALS.done(player,"nuannuan").has(4) \
			and _rest_seat_taken(token,str(goal_parts[2])):
			return fail("這個位子有人坐了，換一個位子或稍等一下。")
		var result:=RESIDENT_GOALS.apply(player,inv,goal_parts,NAMES,state,token)
		if result.ok and goal_resident=="nuannuan":
			match int(goal_parts[1]):
				2:state[WARM_SPRINGS.BATH_KEY]=true
				4:_sit_at_inn(player,str(goal_parts[2]))
		return result
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
		var channel:=str(ORDER_CATALOG.find(extra).get("channel","village"))
		var board:Dictionary=ORDER_BOARDS[channel]
		var at_board:bool=_region==board.region and p==board.cell
		if channel=="dock":
			if not at_board or not state.wangan_star_walk:
				return fail("修好星砂步道後，可到望安碼頭接單和交貨。")
		elif channel=="lanyang":
			if not at_board or not state.lanyang_life.repaired:
				return fail("修好蘭陽水圳後，到星禾的水圳手記接單和交貨。")
		elif not at_board or not state.board:return fail("修好公告板後即可接生活訂單")
		var now:=float(state.time)
		var context:=ORDER_CATALOG.context_from_world(self,token,channel)
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
	if action in ["axe",SEAWEED_POINT] and _region==REGIONS.HOME and p==SEAWEED_CELL:
		var remaining:=ceili(float(state.seaweed_ready)-float(state.time))
		if remaining>0:return fail("海苔還在長，約 %d 秒後可以再採集"%remaining)
		if int(inv.get("seaweed",0))>=1000000000:return fail("背包的海苔已達上限")
		give(inv,"seaweed",1)
		_record_discovery(player,"shore","seaweed")
		state.seaweed_ready=float(state.time)+SEAWEED_REGROW_SECONDS
		player.gathering_points=mini(1000000000,int(player.get("gathering_points",0))+1)
		return ok("採到海苔 ×1，約 %d 秒後可以再採集"%SEAWEED_REGROW_SECONDS)
	if action==SEAWEED_POINT:return fail("請到望安南岸的海苔採集點。")
	if action==WANGAN_COAST.STAR_REPAIR_POINT:
		if _region!=REGIONS.HOME or p!=WANGAN_COAST.STAR_REPAIR or not extra.is_empty():return fail("請靠近星砂海岸的步道工程牌。")
		if state.wangan_star_walk:return fail("星砂海岸的步道已經修好了。")
		for material in WANGAN_COAST.STAR_COST:
			if int(inv.get(material,0))<WANGAN_COAST.STAR_COST[material]:return fail("步道需要 8 木板和 4 纖維。")
		for material in WANGAN_COAST.STAR_COST:give(inv,material,-WANGAN_COAST.STAR_COST[material])
		state.wangan_star_walk=true
		return ok("星砂海岸的步道修好了！沿木棧道去找晶砂。")
	if action==WANGAN_COAST.STAR_SAND_POINT:
		if _region!=REGIONS.HOME or p!=WANGAN_COAST.STAR_SAND or not state.wangan_star_walk:return fail("先修好星砂海岸的步道。")
		var remaining:=ceili(float(state.wangan_star_sand_ready)-float(state.time))
		if remaining>0:return fail("晶砂約 %d 秒後會重新露出。"%remaining)
		if int(inv.get("crystal_sand",0))>=1000000000:return fail("背包的晶砂已達上限。")
		give(inv,"crystal_sand",1)
		state.wangan_star_sand_ready=float(state.time)+WANGAN_COAST.STAR_SAND_RESPAWN
		player.gathering_points=mini(1000000000,int(player.get("gathering_points",0))+1)
		return ok("採到晶砂 ×1，可用來製作溫室玻璃。")
	if action==WANGAN_COAST.SALT_PARCEL_POINT:
		# D06: 北門鹽田寄來的海鹽包。每位玩家每世界日一次、終身有上限；不是海鹽的生產來源（北門才是）。
		if _region!=REGIONS.HOME or p!=WANGAN_COAST.SALT_PARCEL or not extra.is_empty():return fail("請走到星砂步道起點的海鹽包旁。")
		if not state.wangan_star_walk:return fail("先修好星砂海岸的步道，北門鹽田的海鹽才送得到。")
		var parcel_day:=int(WEATHER.day_index(float(state.time)))+1
		var parcel_total:=int(player.get(WANGAN_COAST.SALT_PARCEL_TOTAL_KEY,0))
		if int(player.get(WANGAN_COAST.SALT_PARCEL_DAY_KEY,0))==parcel_day:return fail("今天的海鹽已經領過了，明天再來看看。")
		if parcel_total>=WANGAN_COAST.SALT_PARCEL_LIFETIME:return fail("北門鹽田寄來的試用海鹽已經領完了。想要更多，請到北門鹽田自己曬鹽。")
		if int(inv.get("sea_salt",0))>1000000000-WANGAN_COAST.SALT_PARCEL_AMOUNT:return fail("背包的海鹽已達上限。")
		give(inv,"sea_salt",WANGAN_COAST.SALT_PARCEL_AMOUNT)
		player[WANGAN_COAST.SALT_PARCEL_DAY_KEY]=parcel_day
		player[WANGAN_COAST.SALT_PARCEL_TOTAL_KEY]=parcel_total+1
		return ok("北門鹽田託船捎來的海鹽 ×%d。配上銀線溪魚就能煎香煎溪魚；想要更多，得親自去北門鹽田曬。"%WANGAN_COAST.SALT_PARCEL_AMOUNT)
	if action==WANGAN_COAST.SHELL_POINT:
		if _region!=REGIONS.HOME or p!=WANGAN_COAST.SHELL_CELL:return fail("請到望安南岸的沙灘。")
		if WANGAN_COAST.high_tide(float(state.time)):return fail("潮水蓋住了貝殼，退潮時再來。")
		var remaining:=ceili(float(state.wangan_shell_ready)-float(state.time))
		if remaining>0:return fail("這裡剛採過，約 %d 秒後可以再找。"%remaining)
		if int(inv.get(WANGAN_COAST.SHELL_ITEM,0))>=1000000000:return fail("背包的貝殼已達上限。")
		give(inv,WANGAN_COAST.SHELL_ITEM,1)
		_record_discovery(player,"shore",WANGAN_COAST.SHELL_ITEM)
		state.wangan_shell_ready=float(state.time)+WANGAN_COAST.SHELL_RESPAWN
		player.gathering_points=mini(1000000000,int(player.get("gathering_points",0))+1)
		return ok("撿到潮紋貝殼 ×1，可以帶到出貨箱。")
	if action=="quarry" or (action=="pick" and _region==REGIONS.HOME and p==Vector2i(54,25)):
		if p!=Vector2i(54,25) or not state.board:return fail("先修好公告板，再去東北方公共採石點")
		if float(state.time)<float(state.quarry.ready):return fail("採石點正在露出新石層，約剩 %d 秒"%ceili(float(state.quarry.ready)-float(state.time)))
		state.quarry.hits+=1
		if int(state.quarry.hits)<3:
			return {"ok":true,"message":"採石 · 再 %d 下就能取出石材"%(3-int(state.quarry.hits)),"gather_continue":true}
		give(inv,"stone",6)
		state.quarry={"hits":0,"ready":float(state.time)+45.0}
		return ok("石材 +6！新的石層約 45 秒後就緒，可和朋友輪流採集")
	if action in ["fish_start","fish_catch"]:
		if _region==REGIONS.HOME and WANGAN_COAST.STAR_POOL.has_point(p) and not state.wangan_star_walk:
			return fail("先修好星砂海岸的步道，再到潮池拋竿。")
		if _region == REGIONS.JINGUASHI or _region in MINES.IDS:return fail("這裡沒有可垂釣的水域")
		if _region==REGIONS.Springs.REGION and REGIONS.Springs.spot(p).is_empty():return fail("請到暖泉溪或高地冷泉的岸邊拋竿")
		if _region==REGIONS.Bamboo.REGION and not REGIONS.Bamboo.water(p):return fail("請到竹澗的岸邊拋竿")
		if _region==REGIONS.StarGarden.REGION and not REGIONS.StarGarden.POOL.has_point(p):return fail("請到映星池岸邊拋竿")
		if not water(p):return fail("找一段河岸，對著水面拋竿")
		if action=="fish_start":
			if player.has("fishing"):return fail("魚竿已經放好了，等魚咬鉤後按空白鍵")
			if extra not in ["","standard"]:return fail("找不到這種釣法")
			var rod:=gathering_tool_upgrade("fish",inv)
			if _region==REGIONS.HOME and FISH_MEET.uses_event_cast_rules(state,token,p):rod=""
			player.fishing={"x":p.x,"y":p.y,"ready":float(state.time)+FishingTracking.bite_wait(rod)}
			if not rod.is_empty():player.fishing.rod=rod
			if extra=="standard":
				player.fishing.merge({"aligned_at":player.fishing.ready,"band":0.5,"tracked":0.0})
			return ok("魚竿放好了。等提示出現，再按空白鍵收竿")
		if not player.has("fishing"):return fail("先對水面拋竿吧")
		if int(player.fishing.x)!=p.x or int(player.fishing.y)!=p.y:return fail("請在原本的釣點收竿")
		if player.fishing.has("rod") and _region==REGIONS.HOME and FISH_MEET.uses_event_cast_rules(state,token,p):
			# A line cast before joining still follows the same rules as everyone else's.
			player.fishing.erase("rod")
			player.fishing.ready=float(state.time)+FishingTracking.BITE_SECONDS
			if player.fishing.has("band"):
				player.fishing.merge({"aligned_at":player.fishing.ready,"band":0.5,"tracked":0.0},true)
			return ok("釣魚會使用統一釣具，這竿已重新放好，請等魚咬鉤。")
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
		if _region==REGIONS.HOME and WANGAN_COAST.FISHING_WATER.has_point(p):spot=WANGAN_COAST.FISHING_SPOT
		if _region==REGIONS.HOME and WANGAN_COAST.STAR_POOL.has_point(p):spot=WANGAN_COAST.STAR_POOL_SPOT
		if _region==REGIONS.HOME and STONE_WORKSHOP.fishing_spot(state,p):spot=STONE_WORKSHOP.FISHING_SPOT
		if _region==REGIONS.HOME and STONE_WORKSHOP.shoal_spot(state,p):spot=STONE_WORKSHOP.SHOAL_SPOT
		var result:=Collections.fishing_result(_region,season,total,player,fposmod(float(state.time),WEATHER.DAY_SECONDS),spot,WEATHER.rains(day,_region))
		var fish_id:String=result.id
		if total>=1000000000 or int(inv.get(fish_id,0))>=1000000000:return fail("釣魚紀錄或背包數量已達上限")
		if result.has("counter"):player[result.counter]=result.misses
		give(inv,fish_id,1)
		_record_discovery(player,"fish",fish_id)
		player.fish_caught=int(player.get("fish_caught",0))+1
		player.erase("fishing")
		return {"ok":true,"message":"釣到了"+FISH[fish_id].name+"！可以帶去種子攤出售","fish_species":fish_id}
	if action in ["cook","claim_cook","cancel_cook","queue_cook","cancel_queued_cook"]:
		var stove:Dictionary=state.objects.get(k,{})
		if not INDUSTRY.is_stove(str(stove.get("type",""))):return fail("請靠近小石灶料理")
		# C12: a far-end cell never cooks on its own; the redirect above already resolved the anchor.
		if INDUSTRY.is_stove_extension(stove):return fail("請靠近公共廚房灶台料理")
		if stove.has("cooking") and stove.has("job"):return fail(COOKING_MSG_CORRUPT)
		# T036 queue path: explicit queue actions, or any cook action on a stove
		# that already carries a `cooking` queue. Plain stoves keep the legacy job.
		# The C12 stove has no legacy job: every cook action uses the queue.
		if action in ["queue_cook","cancel_queued_cook"] or stove.has("cooking") or stove.type==INDUSTRY.KITCHEN_STOVE:
			return _cooking_action(token,stove,action,extra)
		if action=="cook":
			if not stove_recipes("stove").has(extra) or not has_recipe(player,extra):return fail("還沒有這份食譜")
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
	if action in ["pet","feed","egg","install_egg_basket"]:
		if p!=CHICKEN_CELL:return fail("請靠近糯米雞")
		var animal:Dictionary=state.animal
		var stored:=int(animal.get("basket_eggs",0))
		if action=="install_egg_basket":
			if animal.has("basket_eggs"):return fail("雞圈已裝好收集籃")
			if int(inv.get("egg_basket",0))<1:return fail("先在工作台做一個收集籃")
			give(inv,"egg_basket",-1)
			animal.basket_eggs=0
			_store_chicken_egg()
			return ok("已裝好雞圈收集籃，房間成員都能收蛋")
		if action=="egg" and stored>0:
			var before_quality:=int(animal.get("basket_eggs_quality",0))
			var amount:=LIVESTOCK.transfer_products(animal,"basket_eggs",inv,"egg",EGG_BASKET_CAPACITY)
			if amount<=0:return fail("背包中的雞蛋已達上限")
			var quality:=before_quality-int(animal.get("basket_eggs_quality",0))
			return ok("從收集籃領取雞蛋 ×%d%s"%[amount,"（含優良 %d 顆）"%quality if quality>0 else ""])
		if action=="pet":
			if float(state.time)-float(state.animal.last_pet)<30:return fail("糯米雞正開心地休息，過一會兒再摸摸牠")
			state.animal.last_pet=state.time
			CHICKEN_CUDDLE.clear(state.animal)
			state.animal.bond+=1
			return ok("糯米雞靠過來蹭蹭你。親密度 +1")
		if action=="feed":
			if stored>=EGG_BASKET_CAPACITY:return fail("收集籃滿了，先收蛋再餵食")
			if float(state.animal.egg_ready)>=0:return fail("糯米雞已吃飽了，等牠下蛋後再餵吧")
			if int(inv.get("feed",0))<1:return fail("先用小石灶把小麥和纖維做成飼料")
			inv.feed-=1
			if not player.has(RESIDENT_GOALS.CHICKEN_FED_KEY):player[RESIDENT_GOALS.CHICKEN_FED_KEY]=float(state.time)
			state.animal.egg_ready=float(state.time)+CHICKEN_EGG_SECONDS
			state.animal[CHICKEN_FEED_FOLLOW.FIELD]=token
			state.animal.bond+=1
			return ok("糯米雞吃飽了！約一分鐘後可以收蛋")
		if float(state.animal.egg_ready)<0:return fail("還沒有雞蛋，先給牠一份飼料")
		if float(state.time)<float(state.animal.egg_ready):return fail("糯米雞還在準備，剩下 %d 秒"%ceili(float(state.animal.egg_ready)-float(state.time)))
		if int(inv.get("egg",0))>=1000000000:return fail("背包中的雞蛋已達上限")
		give(inv,"egg",1)
		if LIVESTOCK.finish_chicken_cycle(animal,int(inv.get("quality_egg",0))<1000000000)>0:
			give(inv,"quality_egg",1)
			return ok("收到了雞蛋和一顆優良雞蛋！")
		return ok("收到了溫暖的雞蛋！雞蛋 +1")
	if action=="picnic":
		if p!=Vector2i(40,29) or not state.board:return fail("先完成渡口公告板，再準備野餐")
		if state.picnic:return fail("野餐已經準備好了，謝謝大家！")
		var contribution:=CHAPTER_ONE.picnic_contribution(state,token)
		if contribution.is_empty():return fail("還需要兩份蘿蔔湯與一份麵包，可在小石灶製作")
		for item in contribution:
			var amount:int=contribution[item]
			inv[item]=int(inv.get(item,0))-amount
			state.picnic_materials[item]+=amount
		if state.picnic_materials.soup==CHAPTER_ONE.PICNIC_PORTIONS.soup and state.picnic_materials.bread==CHAPTER_ONE.PICNIC_PORTIONS.bread:
			state.picnic=true
			state.community = {"table": COMMUNITY.choose_table(state,active_tokens)}
			for who in state.players.values():give(who.inventory,"radish_seed",3)
			return ok("野餐準備好了！每位島民收到三包蘿蔔種子，渡口也掛上了彩旗")
		return ok("料理已放上野餐桌，等大家一起補齊")
	if action == "donate":
		if p!=Vector2i(40,29): return fail("請到渡口公告板捐材料")
		if state.board: return fail("公告板已修好，不必再捐了；河灣橋（Q05）的木材與繩索請按「捐給河灣橋」，橋基到石工台製作。" if STONE_WORKSHOP.project_pending(state) else "公告板已修好，河灣橋已開放！")
		var contribution:=CHAPTER_ONE.board_contribution(state,inv)
		if contribution.wood+contribution.stone==0:return fail("還需要木材或石材，去附近採集吧")
		for material:String in contribution:
			inv[material]=int(inv.get(material,0))-contribution[material]
			state.donations[material]+=contribution[material]
		note_resident_participation(token,"bridge")
		if state.donations.wood>=CHAPTER_ONE.BOARD_COST.wood and state.donations.stone>=CHAPTER_ONE.BOARD_COST.stone:
			_finish_bridge()
			return ok("公告板修好了！可以接生活訂單。用石工台做橋基，再捐木材和繩索修河灣橋。")
		return ok("材料已捐入，謝謝你一起建設小島")
	if action in ["buy","sell"]:
		if p!=Vector2i(43,29): return fail("請靠近小栗的種子攤")
		if action=="buy" and extra=="sapling":
			if player.coins<20:return fail("樹苗需要 20 鈴幣")
			player.coins-=20
			give(inv,"sapling",1)
			return ok("買到一棵樹苗，按 C 選樹苗，再點空地種下")
		if action=="buy" and extra==FLOUR_ITEM:
			# C12/D04: price, daily stock and the 1-per-request quantity are decided here, never by the client.
			var left:=flour_left(player,float(state.time))
			if left<=0:return fail("今天的麵粉賣完了，明天再來；磨坊蓋好後也能自己磨。")
			if int(player.coins)<FLOUR_PRICE:return fail("麵粉一份 %d 鈴幣，鈴幣不足。"%FLOUR_PRICE)
			if int(inv.get(FLOUR_ITEM,0))>=1000000000:return fail("背包中的麵粉已達上限")
			var today:=int(WEATHER.day_index(float(state.time)))
			player.coins=maxi(0,int(player.coins)-FLOUR_PRICE)
			give(inv,FLOUR_ITEM,1)
			player[SAVE_SCHEMA.FLOUR_STALL_KEY]={"day":today,"bought":FLOUR_DAILY-left+1}
			return ok("買到 1 份麵粉（%d 鈴幣）。今天還剩 %d 份。"%[FLOUR_PRICE,left-1])
		if action=="buy" and extra==SUGAR_ITEM:
			# 內容設定集 §11: price, daily stock and the 1-per-request quantity are decided here, never by the client.
			var sugar_stock:=sugar_left(player,float(state.time))
			if sugar_stock<=0:return fail("今天的糖賣完了，明天再來；冬天的甜菜也能自己熬。")
			if int(player.coins)<SUGAR_PRICE:return fail("糖一份 %d 鈴幣，鈴幣不足。"%SUGAR_PRICE)
			if int(inv.get(SUGAR_ITEM,0))>=1000000000:return fail("背包中的糖已達上限")
			var sugar_day:=int(WEATHER.day_index(float(state.time)))
			player.coins=maxi(0,int(player.coins)-SUGAR_PRICE)
			give(inv,SUGAR_ITEM,1)
			player[SAVE_SCHEMA.SUGAR_STALL_KEY]={"day":sugar_day,"bought":SUGAR_DAILY-sugar_stock+1}
			return ok("買到 1 份糖（%d 鈴幣）。今天還剩 %d 份。"%[SUGAR_PRICE,sugar_stock-1])
		if not CROPS.has(extra) and not FISH.has(extra) and not OTHER_SALES.has(extra) and not CROP_CATALOG.quality_item(extra): return fail("這件商品尚未上架")
		if action=="buy":
			if not CROPS.has(extra):return fail("這項物品沒有販售種子")
			if extra in FLOWER_NURSERY.FLOWERS and not FLOWER_NURSERY.home_seed_allowed(state,token,extra):return fail(FLOWER_HOME_SEED_MSG)
			var price:int=CROPS[extra].seed_price
			if int(inv.get(extra+"_seed",0))>=1000000000:return fail("背包中的種子已達上限")
			if player.coins<price: return fail("鈴幣不足，可以先把收成帶來出售")
			player.coins-=price
			give(inv,extra+"_seed",1)
			if int(player.get(RESIDENT_GOALS.CROP_TRADE_KEY,0))==RESIDENT_GOALS.CROP_SOLD and crop_grows_in_season(extra,REGIONS.HOME,p,float(state.time)):
				player[RESIDENT_GOALS.CROP_TRADE_KEY]=RESIDENT_GOALS.SEED_BOUGHT
			return ok("買到一包"+CROPS[extra].name+"種子")
		var count:int=inv.get(extra,0)
		if count<=0: return fail("背包裡沒有這種收成")
		var sale_price:int=CROP_CATALOG.quality_price(extra) if CROP_CATALOG.quality_item(extra) else (int(CROPS[extra].price) if CROPS.has(extra) else (int(FISH[extra].price) if FISH.has(extra) else int(OTHER_SALES[extra])))
		# T093: 存檔檢查不接受超過上限的鈴幣（save_schema.whole），這裡和出貨箱一樣先擋。
		if int(player.coins)>SHIPPING.MAX_COINS-count*sale_price:return fail(COIN_CAP_MSG)
		player.coins+=count*sale_price
		_record_crop_sale(player,extra)
		inv[extra]=0
		return ok("售出 %d 個，獲得 %d 鈴幣"%[count,count*sale_price])
	if action in [MUSHROOM_MAIL.READ,MUSHROOM_MAIL.CLAIM]:
		var box:Dictionary=state.objects.get(k,{})
		if box.get("type")!=INDUSTRY.MUSHROOM_POST or box.get("owner")!=token:
			return fail("請使用自己放置的蘑菇郵箱。")
		return _mushroom_mail_action(player,inv,action,extra)
	if action==INDUSTRY.DESK_DRAFT_ACTION:
		if state.objects.get(k,{}).get("type")!=INDUSTRY.LEAF_DESK:return fail("請靠近落葉書桌再編輯草稿。")
		var draft:=ISLAND_NOTES.clean(extra)
		if draft.is_empty() and not extra.is_empty():return fail("請輸入 120 字內的留言草稿。")
		if draft.is_empty():player.erase(INDUSTRY.DESK_DRAFT_FIELD)
		else:player[INDUSTRY.DESK_DRAFT_FIELD]=draft
		return ok("已清除私人草稿。" if draft.is_empty() else "已儲存私人草稿。")
	if action==WALL_FIXTURES.TOOL_BOARD_WRITE:
		var anchor:=station_anchor(state.objects,p)
		var board:Dictionary=state.objects.get(key(anchor),{})
		if board.get("type")!=WALL_FIXTURES.TOOL_BOARD or board.get("owner")!=token:
			return fail("只有工具板主人能更換展示。")
		var choice:=extra.split(":")
		if choice.size()!=2 or choice[0] not in ["0","1"] or not WALL_FIXTURES.TOOL_LOOKS.has(choice[1]):
			return fail("請選一個掛鉤和工具外觀。")
		var tools:Array=board.get(WALL_FIXTURES.TOOL_BOARD_FIELD,["",""])
		tools[int(choice[0])]=choice[1]
		if tools==["",""]:board.erase(WALL_FIXTURES.TOOL_BOARD_FIELD)
		else:board[WALL_FIXTURES.TOOL_BOARD_FIELD]=tools
		return ok("已更新工具板的展示。")
	if action==BARK_FRAME.ACTION:
		var frame:Dictionary=state.objects.get(k,{})
		if frame.get("type")!=WALL_FIXTURES.BARK_FRAME or frame.get("owner")!=token:
			return fail("只有畫框主人能更換展示。")
		if extra.is_empty():
			frame.erase(BARK_FRAME.FIELD)
			return ok("已收起畫框裡的展示。")
		if not BARK_FRAME.valid_display(extra):return fail("這張照片無法放進畫框。")
		if extra==BARK_FRAME.SKETCH and not RESIDENT_GOALS.done(player,"diandian").has(2):
			return fail("完成點點的第二段故事，才能展示他的速寫。")
		frame[BARK_FRAME.FIELD]=extra
		return ok("畫框已換上新的展示。")
	if action==INDUSTRY.CABINET_ACCESS:
		var cabinet:Dictionary=state.objects.get(k,{})
		if cabinet.get("type") not in [INDUSTRY.ACORN_CABINET,INDUSTRY.TEA_SNACK_SHELF] or cabinet.get("owner")!=token:
			return fail("只有主人能調整收納家具的權限。" if cabinet.get("type")==INDUSTRY.TEA_SNACK_SHELF else "只有櫃主能調整收納櫃的權限。")
		var shelf_name:String="點心架" if cabinet.get("type")==INDUSTRY.TEA_SNACK_SHELF else "收納櫃"
		if extra=="island":cabinet.cabinet_shared=true
		elif extra=="owner":cabinet.erase("cabinet_shared")
		else:return fail("請選擇私人或同島共用。")
		return ok(shelf_name+"已開放同島存取。" if extra=="island" else shelf_name+"已設為私人。")
	if action=="box_deposit_access":
		var box:Dictionary=state.objects.get(k,{})
		if box.get("type")!="private_chest" or box.get("owner")!=token:return fail("只有私人箱的主人能調整存入權限。")
		if extra=="island":box.guest_deposit=true
		elif extra=="owner":box.erase("guest_deposit")
		else:return fail("請選擇有效的存入權限。")
		return ok("存入權限已更新。")
	if action=="box_withdraw_access":
		var box:Dictionary=state.objects.get(k,{})
		if box.get("type")!="private_chest" or box.get("owner")!=token:return fail("只有私人箱的主人能調整取出權限。")
		if extra=="owner":
			box.erase("withdraw_guest")
			return ok("已收回訪客的取出權限。")
		if not extra.begins_with("friend:"):return fail("請選擇有效的取出權限。")
		var guest:=_regional_guest(token,extra.trim_prefix("friend:"))
		if guest.is_empty():return fail("請選擇同區在線的玩家。")
		box.withdraw_guest=guest
		return ok("已開放指定島民查看與取出箱內物品。")
	if action in CHEST_MOVES:
		var box:Dictionary=state.objects.get(k,{})
		if box.get("type","") not in ["chest","private_chest","supply_box",INDUSTRY.ACORN_CABINET]: return fail("這裡沒有箱子")
		var storing:bool=action.begins_with("deposit")
		var floor_piece:Dictionary=state.ground.get(k,{})
		var permission:=PLOT_PERMISSIONS.can_deposit(token,box,floor_piece) if storing else PLOT_PERMISSIONS.can_withdraw(token,box,floor_piece)
		if not permission.ok:return fail(permission.message)
		var item:=extra
		var requested:=0
		if action in CHEST_EXACT_MOVES:
			var parts:=extra.split(":",true,1)
			if parts.size()==2:requested=chest_exact_quantity(parts[1])
			if requested==0:return fail("請輸入有效的存取件數")
			item=parts[0]
		if not NAMES.has(item): return fail("無法存取這項物品")
		if not (box.get("items") is Dictionary):return fail("這裡沒有箱子")
		var source:Dictionary=inv if storing else box.items
		var target:Dictionary=box.items if storing else inv
		var have:=int(source.get(item,0))
		if have<=0:return fail("背包沒有這項物品" if storing else "箱子裡沒有這項物品")
		if requested>have:return fail("背包裡的數量不足" if storing else "箱子裡的數量不足")
		var cabinet:bool=box.type==INDUSTRY.ACORN_CABINET
		if cabinet and storing and not target.has(item) and target.size()>=INDUSTRY.CABINET_SLOTS:
			return fail("收納櫃的 16 格已滿，請先取出一種物品。")
		if storing and BOX_CAPACITY.applies(box.type) and not BOX_CAPACITY.slot_ok(target,{item:1}):
			return fail(BOX_CAPACITY.FULL_MESSAGE)
		var amount:=requested if requested>0 else chest_move_amount(action,have)
		if int(target.get(item,0))>MINE_FREIGHT.LIMIT-amount:
			return fail("箱子中的物品已達上限" if storing else "背包中的物品已達上限")
		if cabinet and not storing and amount==have:source.erase(item)
		else:source[item]=have-amount
		give(target,item,amount)
		SAVE_SCHEMA.CHEST_HISTORY.record(box, str(player.name), item, amount, storing, float(state.time))
		var verb:String="存入" if storing else "取出"
		if action in ["deposit","withdraw"]:return ok("已"+verb+NAMES[item])
		return ok("已%s%s ×%d"%[verb,NAMES[item],amount])
	if action=="door":
		var door:Dictionary=state.objects.get(k,{})
		if door.get("type","")!="door":return fail("這裡沒有門")
		if door.get("open",false):
			for active_token in regional_tokens():
				var who:Dictionary=state.players[active_token]
				var feet:=Vector2(who.x,who.y)
				if feet.distance_to(Vector2(p)+Vector2(0.5,0.5))<0.8 or INDUSTRY.foot_box_hits(feet,[p]):
					return fail("有人站在門口，等他通過再關門")
		door.open=not door.get("open",false)
		return ok("門打開了" if door.open else "門關好了")
	if action=="plant_tree":
		var problem:=tree_planting_problem(token,p)
		if not problem.is_empty():return fail(problem)
		inv.sapling-=1
		state.forest[k]={"growth":0.0,"mature":false,"owner":token}
		player.trees_planted=int(player.get("trees_planted",0))+1
		return ok("種下了樹苗，島上有人時約三分鐘長成，不需要澆水")
	# Existing crops on newly protected routes can still be watered and harvested.
	var legacy_route_crop:bool=false
	if action in ["water","harvest"] and state.crops.has(k):
		legacy_route_crop=REGIONS.transit_walkway(p,_region) or (_region==REGIONS.HOME and WANGAN_COAST.FERRY_ACCESS.has_point(p))
	if water(p) or (protected(p) and action!="remove" and not legacy_route_crop): return fail("這裡是水域或公共通道，請換個位置")
	var r:=resource(p)
	if action in ["axe","pick"]:
		if r=="": return fail("這裡沒有可採集的資源")
		if r=="sapling":return fail("小樹還在長大；自己的樹苗可用拆除工具移回背包")
		if r=="stump":return fail("樹樁會慢慢長回樹木。要清空地面，請用拆除工具。")
		if r=="rock" and action!="pick":return fail("這是石頭，請選十字鎬")
		if r=="tree" and action!="axe":return fail("這是樹木，請選斧頭")
		var hardwood:=r=="tree" and bool(state.forest.get(k,{}).get("mature",false))
		var axe_effect:Dictionary=FORESTRY_AXE_EFFECTS.get(gathering_tool_upgrade("axe",inv),{}) if r=="tree" else {}
		var impact:=2 if r=="rock" and not gathering_tool_upgrade("pick",inv).is_empty() else int(axe_effect.get("impact",1))
		state.damage[k]=int(state.damage.get(k,0))+impact
		var needed:=3 if r=="tree" else 2
		if r=="grass":needed=1
		if state.damage[k]<needed:
			return {"ok":true,"message":"%s · 還需要 %d 下"%["砍樹" if r=="tree" else "採集",needed-int(state.damage[k])],"gather_continue":true,"natural_gather":true}
		var items:Dictionary
		match r:
			"tree":items={"wood":6,"fiber":2,"sapling":1,"resin":1}
			"rock":items={"stone":5}
			"grass":items={"fiber":6 if WEATHER.at(float(state.time),_region).id=="windy" else 4}
		if hardwood:items.hardwood=HARDWOOD_YIELD+int(axe_effect.get("hardwood_bonus",0))
		if not _drop_gather_items(token,k,items):return fail("先撿起地上的材料，再繼續採集。")
		player.gathering_points=mini(1000000000,int(player.get("gathering_points",0))+1)
		for helper:String in gather_assist_candidates(token,p):
			var contributor:Dictionary=state.players[helper]
			contributor.gathering_points=mini(1000000000,int(contributor.get("gathering_points",0))+1)
			contributor.gathering_assists=mini(1000000000,int(contributor.get("gathering_assists",0))+1)
		state.removed[k]=true
		if r=="tree" and not hardwood and _region==REGIONS.HOME and WOODLAND.GROVE.has_point(p):WOODLAND.record_felling(state,k)
		state.forest.erase(k)
		state.damage.erase(k)
		return {"ok":true,"message":"材料掉到地上了，走近就能撿起","gather_dropped":true,"natural_gather":true}
	if action=="hoe":
		if extra=="spread":return _hand_hoe_spread(token,p,inv)
		if r!="" or (state.objects.has(k) and not has_hanging_pot(k)) or state.ground.has(k):return fail("先清空地面，再開墾農田")
		if state.crops.has(k):return fail("這一格已經是農田")
		if _region==FLOWER_NURSERY.REGION:
			if not FLOWER_NURSERY.unlocked(state,token) or not FLOWER_NURSERY.own_record(state,token).intro:return fail("先向花農問好，再開墾育苗床。")
			if not FLOWER_NURSERY.NURSERY_BEDS.has_point(p):return fail(FLOWER_REJECT_MSG)
			if not FLOWER_NURSERY.plot_allowed(state.crops,token):return fail("田尾育苗床每人最多 %d 格，先收成或恢復自己的空床。"%FLOWER_NURSERY.PLOT_CAP)
		_open_farm_soil(token,[k])
		return ok("農田準備好了，接著選種子播種")
	if action=="seed":
		if extra.begins_with("spread:"):return _hand_seed_spread(token,p,inv,extra.trim_prefix("spread:"))
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
		_plant_crop(token,k,extra)
		if _region==FLOWER_NURSERY.REGION:FLOWER_NURSERY.note_plant(state,token,extra)
		if not greenhouse_covers(k) and not crop_grows_in_season(extra,_region,p,float(state.time)):
			return ok("種下%s。現在不是它的季節，會休眠到%s季再生長。"%[CROPS[extra].name,crop_season_text(extra)])
		return ok("種下"+CROPS[extra].name+"，記得澆水")
	if action=="water":
		if extra=="spread":return _hand_water_spread(token,player,p,inv)
		if not state.crops.has(k):return fail("請對農田澆水")
		var plot:Dictionary=state.crops[k]
		var permission:=PLOT_PERMISSIONS.can_water(self,token,plot)
		if not permission.ok:return fail(permission.message)
		return _water_plot(player,plot,plot.get("owner","")==token)
	if action in ["plot_sow_access","plot_water_access"]:
		var sowing:=action=="plot_sow_access"
		var title:="播種" if sowing else "澆水"
		var setting:="owner_sow" if sowing else "owner_water"
		if _region!=REGIONS.HOME:return fail("只有家園農田可調整%s權限。"%title)
		if not state.crops.has(k) or state.crops[k].get("owner","")!=token:return fail("只有田主能調整%s權限。"%title)
		if extra=="owner":state.crops[k][setting]=true
		elif extra=="island":state.crops[k].erase(setting)
		else:return fail("請選擇有效的%s權限。"%title)
		return ok("%s權限已更新。"%title)
	if action=="plot_harvest_access":
		if not state.crops.has(k) or state.crops[k].get("owner","")!=token:return fail("只有田主能調整採收權限。")
		if _region==FLOWER_NURSERY.REGION:return fail("田尾育苗床固定由田主採收。")
		var crop:Dictionary=state.crops[k]
		if extra.begins_with("friend:"):
			var guest:=_regional_guest(token,extra.trim_prefix("friend:"))
			if guest.is_empty():return fail("請選擇同區在線的玩家。")
			crop.harvest_friend=guest
			crop.harvest_access="friend"
			return ok("採收權限已更新。")
		if extra not in ["owner","island"]:return fail("請選擇有效的採收權限。")
		crop.erase("harvest_friend")
		crop.harvest_access=extra
		return ok("採收權限已更新。")
	if action=="harvest":
		if extra=="spread":return _hand_harvest_spread(token,player,p)
		if not state.crops.has(k) or state.crops[k].kind=="":return fail("這裡沒有作物")
		var crop:Dictionary=state.crops[k]
		var permission:=PLOT_PERMISSIONS.can_harvest(self,token,crop)
		if not permission.ok:return fail(permission.message)
		return _harvest_crop_action(token,player,crop,p,k)
	if action=="build":
		# C13: only a plain "mill" while a legacy kit is held keeps the old 1x1 meaning; every other mill
		# build (explicit facing, or no kit in the backpack) is the new 3x3 and defaults to facing 0.
		var placing_facing:=mill_facing
		if extra==INDUSTRY.MILL and placing_facing<0 and int(inv.get("mill_kit",0))<1:placing_facing=0
		return _build_piece(token,p,extra,true,false,true,extra in [INDUSTRY.INN_BED,INDUSTRY.BEACH_CHAIR,INDUSTRY.BAMBOO_LOUNGER,INDUSTRY.GRID_BOOKCASE,INDUSTRY.CEDAR_BED],false,placing_facing)
	if action=="remove":
		if _region==REGIONS.HOME and WOODLAND.stumps(state).has(k):
			WOODLAND.stumps(state).erase(k)
			return ok("已挖除樹樁，可以在這格整地或建造。")
		if state.objects.get(k,{}).get("aru_public",false):return fail("已捐給公共地塊的家具會留給大家使用。")
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
		if state.crops.has(k) and not has_glass_roof(k) and not has_hanging_pot(k):
			if state.crops[k].kind!="":return fail("田裡還有作物，收成後才能恢復草地")
			var permission:=PLOT_PERMISSIONS.can_dismantle(self,token,p)
			if not permission.ok:return fail(permission.message)
			state.crops.erase(k)
			return ok("空農田恢復成草地，可以重新規劃家園了")
		# Automatic roofs are skipped: the object/floor beneath is targeted with
		# its usual owner/busy/contents guards; the roof follows via reconcile.
		var layer_name:=removal_layer
		if layer_name=="":return fail("這裡沒有可拆除的建物")
		var source:Dictionary=state[layer_name]
		# C08: a wide workbench is refunded once, from its anchor. A lone far-end cell (its anchor is
		# gone) can never be dismantled for a second refund.
		if not source.has(k) or INDUSTRY.is_bench_extension(source[k]) or INDUSTRY.is_stove_extension(source[k]) or INDUSTRY.is_mill_extension(source[k]):return fail("這裡沒有可拆除的建物")
		var obj:Dictionary=source[k]
		var permission:=PLOT_PERMISSIONS.can_dismantle(self,token,p,false,layer_name)
		if not permission.ok:return fail(permission.message)
		if obj.type=="conveyor" and (obj.enabled or not obj.items.is_empty()):return fail("請停用並清空輸送帶")
		if obj.type=="mine_drill" and not MINE_DRILL.can_move(obj):return fail("請停用並清空採掘機。")
		if obj.type=="waterworks" and not WATERWORKS.can_move(obj):return fail("請停用並清空水力加工台。")
		if (obj.type in LOGISTICS.PROCESSORS or obj.type in INDUSTRY.MANUAL_STATIONS) and not LOGISTICS.processing_idle(obj):return fail(PROCESSING_MSG_BUSY)
		if obj.type in LOGISTICS.PROCESSORS and not LOGISTICS.processor_ready_to_move(obj):return fail("請停用自動加工並清空設備")
		if obj.type=="forester" and not FORESTRY.can_move(obj):return fail("請先停用林務站並取回全部材料")
		if obj.has("collector_animal"):return fail("先領取產物並取回收集籃，再拆除收集器。")
		if obj.type==INDUSTRY.COAST_CART and obj.get("market_cart_open",false):return fail(INDUSTRY.CART_BUSY)
		if obj.type==INDUSTRY.HOLLOW_BED and _seat_occupied(p):return fail(INDUSTRY.HOLLOW_BUSY)
		if obj.type==INDUSTRY.MUSHROOM_STOOL and _seat_occupied(p):return fail(INDUSTRY.MUSHROOM_STOOL_BUSY)
		if obj.type==INDUSTRY.WOOD_CHAIR and _seat_occupied(p):return fail(INDUSTRY.WOOD_CHAIR_BUSY)
		if obj.type==INDUSTRY.INDIGO_CUSHION and _seat_occupied(p):return fail(INDUSTRY.INDIGO_CUSHION_BUSY)
		if obj.type in RESIDENT_GOALS.INDEPENDENT_TWO_SEATS and _seat_occupied(p):return fail(RESIDENT_GOALS.two_seat_busy(obj.type))
		if obj.type in INDUSTRY.FOUR_SEAT_TABLES:
			if _seat_occupied(p):return fail(INDUSTRY.MUSHROOM_TABLE_BUSY)
			if not obj.items.is_empty():return fail("先收回桌上剩下的餐點，再拆除。")
			if obj.get(INDUSTRY.TEA_SET_FIELD,false):return fail("先取回桌上的小陶茶具，再拆除茶桌。")
		if obj.type=="wall" and state.objects.get(key(p+Vector2i.DOWN),{}).get("type") in WALL_FIXTURES.KINDS:
			return fail(WALL_FIXTURES.REMOVE_MESSAGE)
		if obj.type=="window" and state.objects.get(key(p+Vector2i.DOWN),{}).get("type")==WALL_FIXTURES.BAMBOO_CURTAIN:
			return fail(WALL_FIXTURES.CURTAIN_REMOVE_MESSAGE)
		if obj.has("job"):return fail("設備仍在工作，先領取或取消再拆除")
		if obj.has("cooking") and not cooking_idle(obj):return fail(COOKING_MSG_BUSY)
		if obj.type==INDUSTRY.AQUARIUM and not obj.items.is_empty():return fail("先把紅尾小鯉取回背包，再拆除魚缸。")
		if obj.type==INDUSTRY.COAST_FISH_COUNTER and not obj.items.is_empty():return fail("先取回展示的漁獲，再拆除魚貨台。")
		if obj.type==INDUSTRY.TEA_DISPLAY_CABINET and not obj.items.is_empty():return fail("先取回展示的茶葉，再拆除茶葉展示櫃。")
		if obj.type==INDUSTRY.TEA_SNACK_SHELF and INDUSTRY.snack_total(obj)>0:return fail(INDUSTRY.SNACK_REMOVE_MESSAGE)
		if (obj.type==INDUSTRY.SHELL_TABLE or (obj.type=="table" and obj.items.keys().any(func(item):return item in INDUSTRY.WOOD_TABLE_DISPLAY))) and not obj.items.is_empty():
			return fail("先取回桌上的展示品，再拆除桌子。")
		if obj.type==INDUSTRY.POT_RACK and obj.has("rack_pots"):return fail("先取回架上的花盆，再拆除銅框花架。")
		if obj.type==NURSERY_BOX.KIND and NURSERY_BOX.occupied(obj):return fail(NURSERY_BOX.BUSY_MESSAGE)
		if obj.type==INDUSTRY.BEACH_CHAIR and _seat_occupied(p):return fail(INDUSTRY.BEACH_BUSY)
		if obj.type==INDUSTRY.BAMBOO_LOUNGER:
			if obj.owner!=token:return fail(INDUSTRY.LOUNGER_NOT_OWNER)
			if _seat_occupied(station_anchor(source,p)):return fail(INDUSTRY.LOUNGER_BUSY)
		if obj.type==INDUSTRY.SHELL_TABLE and _seat_occupied(p):return fail(INDUSTRY.SHELL_BUSY)
		for amount in obj.get("items",{}).values():
			if int(amount)>0:return fail("箱子還有物品，先取出再拆除")
		var recipe:Dictionary=BUILD[obj.type]
		if obj.type=="loom" and not obj.get("joinery_loom",false):recipe=LEGACY_LOOM_COST
		if obj.type=="glass_furnace" and not obj.get("iron_furnace",false):recipe=LEGACY_GLASS_FURNACE_COST
		if obj.type=="seed_maker" and not obj.get("joinery_seed_maker",false):recipe=LEGACY_SEED_MAKER_COST
		if obj.type=="jam_pot" and not obj.get("ceramic_pot",false):recipe=LEGACY_JAM_POT_COST
		if obj.type=="window" and obj.get(WOOD_WINDOW_FIELD)!=true:recipe=LEGACY_WINDOW_COST
		if obj.type=="medium_sprinkler" and not obj.get("sprinkler_daily",false):recipe=LEGACY_MEDIUM_SPRINKLER_COST
		if obj.type==INDUSTRY.MILL and INDUSTRY.square_part(obj)<0:recipe=LEGACY_MILL_COST
		if obj.type=="sprinkler" and (obj.get(INDUSTRY.STARTER_SPRINKLER_FIELD,false) or not obj.get("sprinkler_daily",false)):
			recipe=KIT_SPRINKLER_COST
		if obj.get("assembled_sprinkler",false):recipe={INDUSTRY.SPRINKLER_KITS[obj.type]:1}
		var guest_dismantle:bool=obj.owner!=token
		if not state.players.has(obj.owner):return fail("找不到原物主的背包。")
		var refund_inventory:Dictionary=state.players[obj.owner].inventory
		for item in recipe:
			if item!="name" and int(refund_inventory.get(item,0))+int(recipe[item])>1000000000:
				return fail("背包中的物品已達上限")
		for item in recipe:
			if item!="name":give(refund_inventory,item,int(recipe[item]))
		if obj.type==INDUSTRY.CEDAR_BED and state.players[obj.owner].get(INDUSTRY.HOME_REST_FIELD)==k:
			state.players[obj.owner].erase(INDUSTRY.HOME_REST_FIELD)
		if obj.type in RESIDENT_GOALS.DOUBLE_BENCHES:
			_master_bench_clear(p)
			source.erase(key(p+master_bench_offset(obj)))
		if obj.type in [RESIDENT_GOALS.GARDEN_CHAIR,INDUSTRY.SHELL_TABLE,INDUSTRY.MUSHROOM_STOOL,INDUSTRY.WOOD_CHAIR,INDUSTRY.INDIGO_CUSHION]:_master_bench_clear(p)
		if INDUSTRY.square_part(obj)==0:
			if obj.type in [INDUSTRY.FOOT_BATH,INDUSTRY.BEACH_CHAIR,INDUSTRY.BAMBOO_LOUNGER,INDUSTRY.HOLLOW_BED]+INDUSTRY.FOUR_SEAT_TABLES:_master_bench_clear(p)
			for offset:Vector2i in INDUSTRY.station_cells(obj.type,INDUSTRY.is_vertical(obj)):source.erase(key(p+offset))
		source.erase(k)
		if guest_dismantle:return {"ok":true,"message":"已拆除，建造材料已退還物主。","guest_dismantle":true}
		return ok("已拆除，建造材料完整退還")
	return fail("請選擇工具後再試一次")

func _mushroom_mail_action(player:Dictionary,inv:Dictionary,action:String,id:String)->Dictionary:
	if not MUSHROOM_MAIL.eligible(state,player,id):return fail("這封信還沒有送到。")
	var status:Dictionary=player.get(MUSHROOM_MAIL.RECORD,{})
	if action==MUSHROOM_MAIL.READ:
		if not status.has(id):status[id]="read"
		player[MUSHROOM_MAIL.RECORD]=status
		return ok("已讀信件。")
	var items:Dictionary=MUSHROOM_MAIL.LETTERS[id].items
	if items.is_empty():return fail("這封信沒有附包裹。")
	if status.get(id)=="claimed":return fail("這份包裹已經領取。")
	for item:String in items:
		if int(inv.get(item,0))>ITEM_CATALOG.stack_limit(item)-int(items[item]):return fail(MUSHROOM_MAIL.ITEM_LIMIT_MESSAGE)
	for item:String in items:give(inv,item,int(items[item]))
	status[id]="claimed"
	player[MUSHROOM_MAIL.RECORD]=status
	return ok("已把包裹放進背包。")

func _nursery_action(token:String,player:Dictionary,tile:Vector2i,action:String,extra:String)->Dictionary:
	var anchor:=station_anchor(state.objects,tile)
	var box:Dictionary=state.objects.get(key(anchor),{})
	if box.get("type")!=NURSERY_BOX.KIND or box.get("owner")!=token:return fail("只有箱主能照料育苗箱。")
	var parts:=extra.split(":")
	var sowing:=action==NURSERY_BOX.SOW
	if parts.size()!=(2 if sowing else 1) or parts[0] not in ["0","1","2","3"]:return fail("請選擇四格育苗床之一。")
	var slot:String=parts[0]
	var slots:Dictionary=box.get(NURSERY_BOX.SLOTS,{})
	var crop:Dictionary=slots.get(slot,NURSERY_BOX.empty_plot())
	var plot:=NURSERY_BOX.plot_cell(anchor,int(slot),INDUSTRY.is_vertical(box))
	var plot_key:=key(plot)
	if sowing:
		if crop.kind!="":return fail("這格已經種了作物。")
		var kind:String=parts[1]
		if not CROPS.has(kind):return fail("請選擇種子。")
		var problem:=planting_problem(kind,plot)
		if not problem.is_empty():return fail(problem)
		if int(player.inventory.get(kind+"_seed",0))<=0:return fail("背包裡沒有這種種子。")
		give(player.inventory,kind+"_seed",-1)
		crop.kind=kind
		crop.remaining=int(CROPS[kind].get("cycles",1))
		crop.growth=0.0
		slots[slot]=crop
		box[NURSERY_BOX.SLOTS]=slots
		if not greenhouse_covers(plot_key) and not crop_grows_in_season(kind,_region,plot,float(state.time)):
			return ok("種下%s。它會休眠到%s季再生長。"%[CROPS[kind].name,crop_season_text(kind)])
		return ok("種下"+CROPS[kind].name+"，記得澆水。")
	if crop.kind=="":return fail("這格還沒有作物。")
	if action==NURSERY_BOX.WATER:return _water_plot(player,crop,true)
	return _harvest_crop_action(token,player,crop,plot,plot_key,true)

func _water_plot(player:Dictionary,plot:Dictionary,own_plot:bool)->Dictionary:
	var day:=int(WEATHER.day_index(float(state.time)))
	var kind:String=plot.kind
	var cared:=int(player.get("crop_care",0))
	if cared<CROP_CATALOG.CARE_TARGET and not plot.wet and own_plot and CROPS.has(kind) \
		and float(plot.growth)<float(CROPS[kind].time) and int(plot.get("last_care_day",-1))!=day:
		plot.last_care_day=day
		player.crop_care=cared+1
		plot.wet=true
		return ok("水分充足 · 照料 %d／%d%s"%[player.crop_care,CROP_CATALOG.CARE_TARGET,"，下次收成會有優良作物。" if player.crop_care==CROP_CATALOG.CARE_TARGET else ""])
	plot.wet=true
	return ok("水分充足，幼苗會慢慢長大")

func _harvest_crop_action(token:String,player:Dictionary,crop:Dictionary,p:Vector2i,k:String,box_owner:=false)->Dictionary:
	var inv:Dictionary=player.inventory
	if crop.growth<float(CROPS[crop.kind].time):
		if not greenhouse_covers(k) and not crop_grows_in_season(crop.kind,_region,p,float(state.time)):
			return fail("作物正在休眠，等到適合的季節會繼續生長。")
		return fail("還沒成熟，"+("先澆點水吧" if not crop.wet else "再等 %d 秒"%ceili(float(CROPS[crop.kind].time)-float(crop.growth))))
	var crop_name:String=CROPS[crop.kind].name
	var harvested_kind:String=crop.kind
	var bonus:=quality_crop(crop,has_crop_guarantee(player))
	if not bonus.is_empty() and int(inv.get(bonus,0))>=1000000000:return fail("優良作物已達背包上限，作物留在田裡。")
	# T018: same per-item / counter ceiling as harvest_area and SaveSchema.whole; refuse before any mutation.
	if int(inv.get(harvested_kind,0))>1000000000-int(CROPS[harvested_kind].yield):return fail("背包中的"+crop_name+"已達上限，作物留在田裡。")
	if int(player.harvests)>=1000000000:return fail("採收紀錄已達上限，作物留在田裡。")
	var count:=_harvest_plot(token,player,crop,k,box_owner)
	if _region==FLOWER_NURSERY.REGION:FLOWER_NURSERY.note_harvest(state,token,harvested_kind,count)
	var quality_note:="品質收成 · %s +1。"%NAMES[bonus] if not bonus.is_empty() else ""
	return ok("收成了！%s +%d。"%[crop_name,count]+quality_note+("%s還能再收 %d 次，記得重新澆水"%[crop_name,int(crop.remaining)] if crop.kind!="" else "可以出售或帶去做料理"))

func _copper_rack_action(token:String,tile:Vector2i,action:String,extra:String)->Dictionary:
	var rack:Dictionary=state.objects.get(key(station_anchor(state.objects,tile)),{})
	if rack.get("type")!=INDUSTRY.POT_RACK or rack.get("owner")!=token:return fail("只能整理自己的銅框花架。")
	var put:=action==INDUSTRY.POT_RACK_PUT
	var parts:=extra.split(":",true,1)
	if parts.size()!=(2 if put else 1) or not parts[0].is_valid_int():return fail("請選擇花架上的展示位。")
	var index:=int(parts[0])
	if index<0 or index>=INDUSTRY.POT_RACK_SLOTS:return fail("請選擇花架上的展示位。")
	var pots:Array=rack.get("rack_pots",["","",""])
	var inv:Dictionary=state.players[token].inventory
	var pot:=INDUSTRY.POT_RACK_EMPTY
	var flower:=parts[1] if put else str(pots[index])
	if put:
		if not str(pots[index]).is_empty():return fail("這個展示位已有花盆。")
		if flower!=pot and flower not in INDUSTRY.POT_RACK_FLOWERS:return fail("請選陶花盆或已採收的花。")
		if int(inv.get(pot,0))<1 or (flower!=pot and int(inv.get(flower,0))<1):return fail("需要一個陶花盆與你選擇的花。")
		give(inv,pot,-1)
		if flower!=pot:give(inv,flower,-1)
		pots[index]=flower
	else:
		if flower.is_empty():return fail("這個展示位還沒有花盆。")
		if not ITEM_CATALOG.can_hold(pot,int(inv.get(pot,0))+1) or (flower!=pot and not ITEM_CATALOG.can_hold(flower,int(inv.get(flower,0))+1)):
			return fail("背包空間不足，花盆先留在架上。")
		give(inv,pot,1)
		if flower!=pot:give(inv,flower,1)
		pots[index]=""
	if pots.count("")==INDUSTRY.POT_RACK_SLOTS:rack.erase("rack_pots")
	else:rack.rack_pots=pots
	if not put:return ok("已把花盆收回背包。")
	return ok("放上了陶花盆。" if flower==pot else "放上了一盆展示花。")

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
	if not PLOT_PERMISSIONS.can_take(token,box,state.ground.get(parts[0],{})).ok:return {}
	return box

static func nearby_dye_furniture(objects:Dictionary, actor:String, table:Vector2i) -> Array[String]:
	var keys:Array[String]=[]
	for y in range(table.y-INDUSTRY.DYE_REACH,table.y+INDUSTRY.DYE_REACH+1):
		for x in range(table.x-INDUSTRY.DYE_REACH,table.x+INDUSTRY.DYE_REACH+1):
			if absi(x-table.x)+absi(y-table.y)>INDUSTRY.DYE_REACH:continue
			var tile:=key(Vector2i(x,y))
			var furniture:Dictionary=objects.get(tile,{})
			if furniture.get("owner")==actor and furniture.get("type") in INDUSTRY.DYEABLE_FURNITURE and INDUSTRY.square_part(furniture)<=0:
				keys.append(tile)
	return keys

func _dye_furniture(token:String,table:Vector2i,extra:String) -> Dictionary:
	var station:Dictionary=state.objects.get(key(table),{})
	if station.get("type")!=INDUSTRY.DYE_TABLE or station.get("owner")!=token:
		return fail("只能在自己的染色桌換色。")
	var parts:=extra.split("|")
	if parts.size()!=2 or not parts[0] in nearby_dye_furniture(state.objects,token,table):
		return fail("請選擇染色桌附近自己的床、桌、椅或沙發。")
	var pigment:=parts[1]
	var furniture:Dictionary=state.objects[parts[0]]
	if furniture.get("dye","")==pigment:return fail("這件家具已經是這個顏色。")
	if pigment.is_empty():
		furniture.erase("dye")
		return ok("已恢復原色。")
	if not INDUSTRY.FURNITURE_DYES.has(pigment):return fail("找不到這種染料。")
	var inv:Dictionary=state.players[token].inventory
	if int(inv.get(pigment,0))<1:return fail("需要一份"+NAMES[pigment]+"。")
	give(inv,pigment,-1)
	furniture.dye=pigment
	return ok("換好了"+INDUSTRY.FURNITURE_DYES[pigment]+"。")

static func assembly_recipe(kind:String) -> Dictionary:
	if kind==INDUSTRY.ANIMAL_COLLECTOR:return INDUSTRY.COLLECTOR_MATERIALS.duplicate()
	if not INDUSTRY.SPRINKLER_KITS.has(kind):return {}
	var ingredients:Dictionary=BUILD[kind].duplicate()
	ingredients.erase("name")
	return ingredients

static func sprinkler_level(kind:String) -> int:
	return {"medium_sprinkler":MEDIUM_SPRINKLER_LEVEL,"large_sprinkler":LARGE_SPRINKLER_LEVEL}.get(kind,1)

func _assemble(player:Dictionary,station:Dictionary,token:String,kind:String) -> Dictionary:
	if station.get("type")!=INDUSTRY.ASSEMBLY_TABLE or station.get("owner")!=token:
		return fail("只能使用自己的裝配桌。")
	var ingredients:=assembly_recipe(kind)
	if ingredients.is_empty():return fail("找不到這份裝配配方。")
	if farming_level(player)<sprinkler_level(kind):return fail("農耕需達到 %d 級。"%sprinkler_level(kind))
	var inv:Dictionary=player.inventory
	var kit:String=INDUSTRY.assembly_items()[kind]
	if int(inv.get(kit,0))>=1000000000:return fail("背包中的物品已達上限。")
	for item in ingredients:
		if int(inv.get(item,0))<int(ingredients[item]):return fail("裝配材料不足。")
	for item in ingredients:give(inv,item,-int(ingredients[item]))
	give(inv,kit,1)
	player.crafting_points=mini(1000000000,int(player.get("crafting_points",0))+1)
	return ok("已裝配："+NAMES[kit])

## C16 紅陶瓦屋頂: validates laying terracotta on every tile of `keys` (current
## region) without mutating anything. Each tile needs a structural floor; an
## existing roof is only accepted when `retile` is set and it is a thatch roof
## the actor may re-tile (TERRACOTTA_ROOF.replaceable). `refunds` maps the payer
## of each replaced thatch roof to the number of tiles to refund; it is applied
## with _terracotta_refund() once the tiles themselves have been paid.
func _terracotta_sites(token:String,keys:Array,retile:bool,area:bool) -> Dictionary:
	var refunds:Dictionary={}
	for tile_key in keys:
		if not ROOM_ENCLOSURE.is_floor_piece(state.ground.get(tile_key)):return fail(TERRACOTTA_ROOF.MSG_AREA if area else TERRACOTTA_ROOF.MSG_FLOOR)
		if not state.roofs.has(tile_key):continue
		var existing=state.roofs[tile_key]
		if area and not (retile and TERRACOTTA_ROOF.replaceable(existing,token)):return fail(TERRACOTTA_ROOF.MSG_AREA)
		if existing is Dictionary and existing.get("type")==TERRACOTTA_ROOF.KIND:return fail(TERRACOTTA_ROOF.MSG_OCCUPIED)
		if not retile or not TERRACOTTA_ROOF.replaceable(existing,token):return fail(TERRACOTTA_ROOF.MSG_OTHER_ROOF)
		# The new roof belongs to the actor; a hanger of someone else would lose its support.
		var hanger:Dictionary=state.objects.get(tile_key,{})
		if hanger.get("type")==ROOF_FIXTURES.HANGING_POT and hanger.get("owner")!=token:return fail(TERRACOTTA_ROOF.MSG_HANGER)
		var payer:=str(existing.owner)
		if not state.players.has(payer):return fail(TERRACOTTA_ROOF.MSG_PAYER)
		refunds[payer]=int(refunds.get(payer,0))+1
	for payer in refunds:
		var back:Dictionary=state.players[payer].inventory
		for item in BUILD.roof:
			if item!="name" and int(back.get(item,0))+int(BUILD.roof[item])*int(refunds[payer])>1000000000:return fail(TERRACOTTA_ROOF.MSG_FULL)
	return {"ok":true,"message":"","refunds":refunds}

## Returns the thatch of re-tiled roofs to the players who paid for it.
func _terracotta_refund(refunds:Dictionary) -> void:
	for payer in refunds:
		var back:Dictionary=state.players[payer].inventory
		for item in BUILD.roof:
			if item!="name":give(back,item,int(BUILD.roof[item])*int(refunds[payer]))

static func build_recipe(kind:String, inventory:Dictionary) -> Dictionary:
	var recipe:Dictionary=BUILD[kind]
	var kit:String=INDUSTRY.SPRINKLER_KITS.get(kind,"")
	if not kit.is_empty() and int(inventory.get(kit,0))>0:return {"name":recipe.name,kit:1}
	if kind=="sprinkler" and int(inventory.get("sprinkler_kit",0))>0:
		if int(inventory.get("copper_ingot",0))<int(recipe.copper_ingot) or int(inventory.get("stone",0))<int(recipe.stone):
			return KIT_SPRINKLER_COST
	return recipe

## Single-piece build rules shared by `build` and blueprints. Callers have
## already applied the region/distance/water/protected gates of _apply.
## charge=false (blueprint simulation only) skips ONLY the inventory check and
## debit; every placement, unlock, limit and collision rule still applies.
func _build_piece(token: String, p: Vector2i, extra: String, charge: bool = true, bench_vertical:bool=false, wide_station:=true, station_vertical:=false, defer_roof_support:=false, mill_facing:int=-1) -> Dictionary:
	if not allows_public_build(token,p):return fail(PUBLIC_BUILD_DENIED)
	var player: Dictionary=state.players[token]
	var inv: Dictionary=player.inventory
	var k := key(p)
	var r:=resource(p)
	if not BUILD.has(extra):return fail("尚未解鎖這個物件")
	if extra==WALL_FIXTURES.BARK_FRAME and not RESIDENT_GOALS.done(player,"diandian").has(2):return fail(RESIDENT_GOALS.BARK_FRAME_LOCK)
	# T12: one server-side gate shared by the normal build action and blueprint quote/apply
	# (both end here). The unlock is this player's own persisted chacha stage-3 completion.
	if extra==INDUSTRY.IMPERFECT_TEA_PAVILION:
		if not PAVILION.unlocked(player):return fail(PAVILION.LOCK_MESSAGE)
		if station_vertical:return fail(PAVILION.BLOCKED_MESSAGE)
	if extra not in BLUEPRINT_DESIGN.GROUND_KINDS and extra not in BLUEPRINT_DESIGN.ROOF_KINDS:
		var floor_permission:=PLOT_PERMISSIONS.placement_floor(self,token,p)
		if not floor_permission.ok:return fail(floor_permission.message)
	if extra==INDUSTRY.HEDGEHOG_BASKET and _region==REGIONS.HOME and Hedgehog.is_food_site(p):return fail("請把午睡籃放在食盤旁的空地。")
	if extra==INDUSTRY.FOOT_BATH and _region!=REGIONS.HOME:return fail("暖石泡腳池只能在家園建造。")
	if extra==INDUSTRY.COAST_REGISTER and _region!=REGIONS.HOME:return fail("白木收銀櫃可放在風鈴渡口的家園。")
	if extra==INDUSTRY.COAST_CART and (_region!=REGIONS.HOME or not MARKET.unlocked(state)):
		return fail("完成渡口野餐後，可在風鈴渡口的家園建造招牌攤車。")
	if extra==INDUSTRY.FOOT_BATH and not RESIDENT_GOALS.done(player,"nuannuan").has(2):
		return fail("完成暖暖的〈池邊的裂縫〉後可建造暖石泡腳池。")
	if extra in RESIDENT_GOALS.DOUBLE_BENCHES:
		if extra==RESIDENT_GOALS.MASTER_BENCH and (_region!=REGIONS.HOME or not RESIDENT_GOALS.done(player,"aru").has(2)):
			return fail("先完成阿榆的長椅修繕關係事件，再回家園建造。")
		var available:=_footprint_space(token,p,[Vector2i.ZERO,Vector2i.DOWN if bench_vertical else Vector2i.RIGHT])
		if not available.ok:return available
	if extra in ["author_sign","author_shelf"] and crafting_level(player)<10:return fail("手作達到十級後解鎖工匠家具。")
	if extra==INDUSTRY.SMELTER and _region!=REGIONS.HOME:return fail("小熔爐只能在家園建造。")
	if extra=="glass_furnace" and not MINES.hoist_ready(state.mine_depths):return fail(GLASS_FURNACE_LOCKED_MSG)
	var square:=extra in INDUSTRY.FIXED_SQUARE_STATIONS or (extra in INDUSTRY.EXPANDABLE_STATIONS and wide_station)
	if extra==INDUSTRY.ANIMAL_COLLECTOR and (_region!=REGIONS.HOME or not state.picnic):return fail("請在完成野餐後的風鈴渡口放置收集器。")
	if extra==INDUSTRY.ASSEMBLY_TABLE and not player.get("workshop_upgraded",false):return fail("先到工作台完成工坊升級。")
	if extra==INDUSTRY.DYE_TABLE and not state.flower_nursery.garden.complete:return fail("完成田尾公共花園後，即可建造染色桌。")
	# C11: the station needs the Q03 board flag; new stone floors / small smelters need the station.
	# Only new construction passes here: undo restore, load and move never call _build_piece.
	if extra==INDUSTRY.STONE_WORKBENCH and state.get("board",false)!=true:return fail(STONE_WORKSHOP.LOCKED_MSG)
	if extra in STONE_WORKSHOP.STATION_BUILDS and not STONE_WORKSHOP.has_station(home_layer("objects")):return fail(STONE_WORKSHOP.STATION_MSG)
	# C08: direct builds are always the new 2x1 bench; a blueprint asks for it with settings.wide
	# so a captured legacy 1x1 bench is rebuilt as a legacy 1x1 bench (same 20 wood + 5 stone).
	var wide_bench:=extra==INDUSTRY.WORKBENCH and wide_station
	# C13: a mill build with a facing (0..3) is the new 3x3; -1 is the legacy kit-paid 1x1 (a blueprint piece
	# without settings.facing, or a plain build while a mill_kit is held).
	var new_mill:=extra==INDUSTRY.MILL and mill_facing>=0
	if extra==INDUSTRY.MILL and mill_facing>=INDUSTRY.MILL_FACING_COUNT:return fail("磨坊的入口方向只能是 0 到 3")
	var has_footprint:=square or wide_bench or new_mill or extra in INDUSTRY.ORIENTABLE_FOOTPRINTS
	var front_problem:=_mill_front_claim_problem(extra,p,has_footprint,station_vertical,Vector2i(-1000,-1000),INDUSTRY.mill_entrance_offset(mill_facing) if new_mill else Vector2i(-1000,-1000))
	if front_problem.is_empty() and extra in RESIDENT_GOALS.DOUBLE_BENCHES:
		front_problem=_mill_front_claim_problem(extra,p+(Vector2i.DOWN if bench_vertical else Vector2i.RIGHT),false)
	if not front_problem.is_empty():return fail(front_problem)
	if extra==WALL_FIXTURES.TOOL_BOARD and (station_vertical or not WALL_FIXTURES.has_tool_board_support(state.objects,p,token,state.edges)):
		return fail(WALL_FIXTURES.TOOL_BOARD_SUPPORT)
	if extra==INDUSTRY.LEAF_MAT:
		for offset:Vector2i in INDUSTRY.SQUARE_CELLS:
			var tile:=p+offset
			var tile_key:=key(tile)
			if not allows_public_build(token,tile):return fail(PUBLIC_BUILD_DENIED)
			var permission:=PLOT_PERMISSIONS.can_place(self,token,tile,extra)
			if not permission.ok:return fail(permission.message)
			if water(tile) or protected(tile) or resource(tile)!="" or state.crops.has(tile_key) or state.ground.has(tile_key) or state.objects.has(tile_key):
				return fail("葉片地墊需要 2×2 的空地。")
	elif has_footprint:
		if extra==INDUSTRY.IMPERFECT_TEA_PAVILION:
			var essential:=pavilion_site_problem(p)
			if not essential.is_empty():return fail(essential)
		# The open shelter can be walked through, so people standing in it never block placement.
		# The mill checks its own people below: only the eight solid cells keep a person out.
		var available:=_footprint_space(token,p,INDUSTRY.station_cells(extra,station_vertical),Vector2i(-1000,-1000),extra!=WALL_FIXTURES.TOOL_BOARD and extra!=INDUSTRY.IMPERFECT_TEA_PAVILION and not new_mill)
		if not available.ok:return available
		if new_mill:
			var mill_problem:=_mill_site_problem(p,mill_facing)
			if not mill_problem.is_empty():return fail(mill_problem)
		if extra==INDUSTRY.RIVERSIDE_SCREEN and _riverside_screen_occupied(p,station_vertical):return fail(INDUSTRY.RIVERSIDE_OCCUPIED)
	if extra==RESIDENT_GOALS.FESTIVAL_BELL and not RESIDENT_GOALS.done(player,"lingpopo").has(3):
		return fail("先完成鈴婆婆的〈最後一枚鈴〉，才能使用紀念鐘圖樣。")
	if extra==RESIDENT_GOALS.BASIC_TEA_SET and (_region!=REGIONS.HOME or not RESIDENT_GOALS.done(player,"chacha").has(1)):
		return fail("完成茶茶的第一席茶後可建造基本茶具。")
	if extra=="wood_mailbox" and (_region!=REGIONS.HOME or not RESIDENT_GOALS.done(player,"luoluo").has(1)):
		return fail("完成洛洛的送信事件後可建造普通信箱。")
	if extra=="guest_wardrobe" and (_region!=REGIONS.HOME or not RESIDENT_GOALS.done(player,"nuannuan").has(3)):
		return fail("完成暖暖的客房事件後可建造旅舍更衣櫃。")
	if extra==RESIDENT_GOALS.COAST_WARDROBE and _region!=REGIONS.HOME:return fail("藍白更衣棚可放在家園。")
	if extra==RESIDENT_GOALS.FOREST_WARDROBE and _region!=REGIONS.HOME:return fail("森林小衣櫃可放在家園。")
	if extra==INDUSTRY.CEDAR_BED and _region!=REGIONS.HOME:return fail("原木小床可放在家園。")
	if extra==WELCOME_SIGN.KIND and not RESIDENT_GOALS.done(player,"nuannuan").has(1):
		return fail("完成暖暖的〈一直沒亮的門牌〉後可建造旅舍迎賓牌。")
	if extra=="sketch_easel" and (_region!=REGIONS.HOME or not RESIDENT_GOALS.done(player,"diandian").has(1)):
		return fail("完成點點的速寫事件後，可在渡口建造小畫架。")
	if extra=="expedition_tent" and exploration_level(exploration_points(player))<EXPEDITION_TENT_LEVEL:return fail("探索達到十級後解鎖探險紀念帳篷。")
	if extra=="supply_box" and not supply_box_unlocked(player):return fail("探索達到六級，或完成波波的休息站事件後可放置便攜補給箱。")
	if extra=="fish_display" and Collections.angling_level(player)<Collections.FISH_DISPLAY_LEVEL:return fail("漁獵觀察達到十級後，即可建造島岸魚譜展示櫃。")
	if extra=="master_flower_bed" and farming_level(player)<MASTER_FARMING_LEVEL:return fail("農耕達到十級後，即可建造豐收花圃。")
	if extra=="greenhouse_rack" and not RESIDENT_GOALS.flower_rack_unlocked(player):return fail("完成星禾的「空花圃的圖紙」或「冬天也開花」後解鎖。")
	if extra==POSTCARDS.RACK and not RESIDENT_GOALS.done(player,"luoluo").has(2):return fail(POSTCARDS.UNLOCK_MESSAGE)
	if extra==NURSERY_BOX.KIND and not RESIDENT_GOALS.done(player,"xinghe").has(3):return fail(NURSERY_BOX.UNLOCK_MESSAGE)
	if extra=="medium_sprinkler" and farming_level(player)<MEDIUM_SPRINKLER_LEVEL:return fail("農耕達到六級後，即可建造中型灑水器。")
	if extra=="large_sprinkler" and farming_level(player)<LARGE_SPRINKLER_LEVEL:return fail("農耕達到八級後，即可建造大型灑水器。")
	if extra=="seed_maker" and farming_level(player)<SEED_MAKER_LEVEL:return fail("農耕達到三級後，即可建造種子機。")
	if extra=="jam_pot" and not MARKET.unlocked(state):return fail("先完成渡口野餐，開放小島市集後再建造果醬鍋。")
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
	var retile:Dictionary={}
	if GREENHOUSE_GLASS.is_glass(extra):
		if state.roofs.has(k):return fail("這裡已經有屋頂")
		if WEATHER.is_indoor(_region):return fail("溫室玻璃棚需要露天農田")
		if extra==GREENHOUSE_GLASS.XINGHE_ROOF:
			if not RESIDENT_GOALS.done(player,"xinghe").has(3):return fail("完成星禾的〈不必把冬天趕走〉後可建造。")
			if r!="" or state.objects.get(k,{}).get("type","") in ROOM_ENCLOSURE.BOUNDARY:
				return fail("請在圍牆內的農田、地板或空地搭設溫室頂。")
		var permission:=PLOT_PERMISSIONS.can_place(self,token,p,extra)
		if not permission.ok:return fail(permission.message)
	elif extra=="roof":
		if state.roofs.has(k):return fail("這裡已經有屋頂")
		if not ROOM_ENCLOSURE.is_floor_piece(state.ground.get(k)):return fail("先鋪地板，再蓋上屋頂")
		var permission:=PLOT_PERMISSIONS.can_place(self,token,p,extra)
		if not permission.ok:return fail(permission.message)
	elif extra==TERRACOTTA_ROOF.KIND:
		# Blueprints (charge=false) never re-tile: their quote prices pieces only.
		var site:=_terracotta_sites(token,[k],charge,false)
		if not site.ok:return fail(site.message)
		var permission:=PLOT_PERMISSIONS.can_place(self,token,p,extra)
		if not permission.ok:return fail(permission.message)
		retile=site.refunds
	elif extra==ROOF_FIXTURES.HANGING_POT:
		if r!="" or state.objects.has(k):return fail("這格已有物件，請選其他掛點。")
		if not defer_roof_support and not ROOF_FIXTURES.supported(state.roofs.get(k),token):
			return fail(ROOF_FIXTURES.SUPPORT_MESSAGE)
	elif r!="" or state.crops.has(k) or (state.objects.has(k) and not (ROOM_ENCLOSURE.is_floor_kind(extra) and state.objects[k].type==INDUSTRY.BRAIDED_RUG and state.objects[k].owner==token)):
		return fail("這格有東西，請選空地")
	if extra in ["floor","stone_floor","path","spring_pebble_path"] and state.ground.has(k):return fail("這裡已經鋪好了")
	if extra in WALL_FIXTURES.KINDS and not WALL_FIXTURES.has_support(state.objects,p,token,extra,state.edges):
		return fail(WALL_FIXTURES.support_message(extra))
	if extra=="water_pump" and not INDUSTRY.near_river(self,p):return fail("水泵需放在河水兩格內的陸地")
	if extra in ["sprinkler","medium_sprinkler","large_sprinkler","forester","conveyor"] or INDUSTRY.LIMITS.has(extra):
		var limit:int={"sprinkler":SPRINKLER_LIMIT,"medium_sprinkler":SPRINKLER_LIMIT,"large_sprinkler":SPRINKLER_LIMIT,"forester":FORESTRY.LIMIT,"conveyor":LOGISTICS.BELT_LIMIT}.get(extra,INDUSTRY.LIMITS.get(extra,0))
		var owned:=0
		for device in state.objects.values():
			if device.type==extra and device.owner==token:owned+=1
		if owned>=limit:return fail("已達此設備的每人放置上限")
	if extra in ["ore_display","wall","window","door","chest","private_chest","supply_box","bench","bed",INDUSTRY.CEDAR_BED,INDUSTRY.MUSHROOM_STOOL,INDUSTRY.MUSHROOM_TABLE,INDUSTRY.BAMBOO_TEA_TABLE,INDUSTRY.TEA_DISPLAY_CABINET,INDUSTRY.TEA_SNACK_SHELF,INDUSTRY.HOLLOW_BED,INDUSTRY.ACORN_CABINET,"inn_quilt_bed","inn_stone_footbath","table",INDUSTRY.ROUNDED_TABLE,INDUSTRY.GRID_BOOKCASE,"stove","long_bench","sofa","planter","sketch_easel","guest_wardrobe","inn_lattice_wardrobe",RESIDENT_GOALS.COAST_WARDROBE,RESIDENT_GOALS.FOREST_WARDROBE,"inn_fabric_screen","wood_mailbox",INDUSTRY.MUSHROOM_POST,INDUSTRY.QUIET_BIRDHOUSE,"rope_rack",POSTCARDS.RACK,"towel_rack","inn_tea_table","inn_luggage_rack","flower_pot","greenhouse_rack","garden_basin",RESIDENT_GOALS.GARDEN_CHAIR,"crop_observation_desk",INDUSTRY.LEAF_DESK,INDUSTRY.SEED_CABINET,NURSERY_BOX.KIND,INDUSTRY.AQUARIUM,INDUSTRY.COAST_FISH_COUNTER,INDUSTRY.COAST_REGISTER,INDUSTRY.COAST_CART,INDUSTRY.SHELL_TABLE,INDUSTRY.GLASS_FLOWER_TABLE,INDUSTRY.VINE_ARCH,INDUSTRY.FOREST_ARCH,INDUSTRY.POT_RACK,"master_flower_bed","fish_display","author_sign","author_shelf","expedition_tent","sprinkler","medium_sprinkler","large_sprinkler","water_tank","water_tower","water_pump","waterworks","mine_drill","sawmill","charcoal_kiln","forester","mill","seed_maker","loom","glass_furnace","jam_pot","clay_kiln","dye_table","assembly_table","animal_collector",INDUSTRY.STONE_WORKBENCH,INDUSTRY.KITCHEN_STOVE]:
		for active_token in regional_tokens():
			var who:Dictionary=state.players[active_token]
			if Vector2(who.x,who.y).distance_to(Vector2(p)+Vector2(0.5,0.5))<0.8:return fail("這裡有人，請留出空間")
	# C13: the legacy 1x1 mill is still paid with its kit; the new 3x3 is paid with BUILD.mill materials.
	var recipe:Dictionary=LEGACY_MILL_COST if extra==INDUSTRY.MILL and not new_mill else (build_recipe(extra,inv) if charge else BUILD[extra])
	if charge:
		for item in recipe:
			if item=="name":continue
			if int(inv.get(item,0))<int(recipe[item]):return fail("材料不足，需要"+NAMES[item]+" %d"%int(recipe[item]))
		for item in recipe:
			if item!="name":give(inv,item,-int(recipe[item]))
	_terracotta_refund(retile)
	var obj:Dictionary={"type":extra,"owner":token,"items":{}}
	if extra in ["author_sign","author_shelf","expedition_tent",WALL_FIXTURES.HOME_SIGN]:obj.author=player.name
	if INDUSTRY.SPRINKLER_CAPACITIES.has(extra):
		obj.merge({"water":0,"enabled":false,"next_water":float(state.time),"last_water":-1.0,"sprinkler_daily":true})
		if recipe.has("sprinkler_kit"):obj[INDUSTRY.STARTER_SPRINKLER_FIELD]=true
	if INDUSTRY.SPRINKLER_KITS.has(extra) and recipe.has(INDUSTRY.SPRINKLER_KITS[extra]):obj.assembled_sprinkler=true
	if extra==INDUSTRY.TEA_SNACK_SHELF:obj[INDUSTRY.SNACK_FIELD]=INDUSTRY.fresh_snack_tiers()
	if extra=="jam_pot":obj.ceramic_pot=true
	if extra=="seed_maker":obj.joinery_seed_maker=true
	if extra=="window":obj[WOOD_WINDOW_FIELD]=true
	if extra=="loom":obj.joinery_loom=true
	if extra=="glass_furnace":obj.iron_furnace=true
	if has_footprint and extra!=INDUSTRY.SMELTER:obj[INDUSTRY.square_part_field(extra)]=0
	if new_mill:obj[INDUSTRY.MILL_FACING]=mill_facing
	if (wide_bench or extra in INDUSTRY.ORIENTABLE_FOOTPRINTS) and station_vertical:obj[INDUSTRY.vertical_field(extra)]=true
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
	elif extra in BLUEPRINT_DESIGN.GROUND_KINDS:state.ground[k]=obj
	else:state.objects[k]=obj
	if extra in RESIDENT_GOALS.DOUBLE_BENCHES:
		if bench_vertical:obj.bench_vertical=true
		_master_bench_end(p,obj)
	if has_footprint:_write_station_parts(p,obj,"ground" if extra==INDUSTRY.LEAF_MAT else "objects")
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
	var includes_edges:bool=int(bp.version)==2
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
	if includes_edges and region!=REGIONS.HOME:
		quote.message="請回到家園再施工沿格線的牆段"
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
	sim.public_build_access=public_build_access
	sim._region=_region
	sim.active_tokens=active_tokens.duplicate()
	sim.switch_region(region)
	var sim_layers:Dictionary=sim._layers_of(region)
	var prior:={}
	for field in CONSTRUCTION_HISTORY.TILE_LAYERS:
		var layer:Dictionary=sim_layers[field]
		# Pieces only add entries, so shallow copies freeze the "before" layers.
		prior[field]=layer.duplicate() if field in CONSTRUCTION_UNDO.LAYERS or field=="edges" else layer
	var problems:Array=[]
	var problem_count:=0
	var touched:Array[Vector2i]=[]
	var topology:={}
	var cells:={}
	var edges:={}
	var hanger_sites:Array[Vector2i]=[]
	var placement_order:=pieces
	if includes_edges:
		var floors:Array=[]
		var walls:Array=[]
		var others:Array=[]
		for piece:Dictionary in pieces:
			if str(piece.kind) in BLUEPRINT_DESIGN.GROUND_KINDS:floors.append(piece)
			elif BLUEPRINT_DESIGN.is_edge_kind(piece.kind):walls.append(piece)
			else:others.append(piece)
		placement_order=floors+walls+others
	for item in placement_order:
		var piece:Dictionary=item
		var kind:=str(piece.kind)
		var c:=origin+Vector2i(int(piece.x),int(piece.y))
		var edge_piece:=BLUEPRINT_DESIGN.is_edge_kind(kind)
		var edge:Dictionary={}
		var side:=int(piece.get("settings",{}).get("side",-1))
		var reason:String
		if edge_piece:
			edge=EDGE_CONSTRUCTION.decode("build_edge",c,kind+"|"+str(side),SIZE)
			reason=EDGE_CONSTRUCTION.stage_blueprint(sim,token,edge)
		else:
			reason=sim._blueprint_piece(token,c,kind,piece.get("settings",{}),str(piece.get("style","")))
		if reason!="":
			problem_count+=1
			if problems.size()<BLUEPRINT_MAX_PROBLEMS:problems.append({"x":c.x,"y":c.y,"kind":kind,"reason":reason})
			continue
		if edge_piece:
			edges[edge.id]=true
			for adjacent:Vector2i in edge.cells:
				if not topology.has(adjacent):
					topology[adjacent]=true
					touched.append(adjacent)
			continue
		cells[key(c)]=true
		if kind==ROOF_FIXTURES.HANGING_POT:hanger_sites.append(c)
		if BLUEPRINT_DESIGN.is_square_piece(piece) or BLUEPRINT_DESIGN.is_wide_bench_piece(piece) or BLUEPRINT_DESIGN.is_mill_piece(piece) or kind in INDUSTRY.ORIENTABLE_FOOTPRINTS:
			for offset:Vector2i in INDUSTRY.station_cells(kind,piece.get("settings",{}).get("vertical",false)):cells[key(c+offset)]=true
		if kind in RESIDENT_GOALS.DOUBLE_BENCHES:cells[key(c+BLUEPRINT_DESIGN.bench_offset(piece))]=true
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
		plan=AUTO_ROOF_PLAN.reconcile(prior,sim.state,touched,token,BUILD.roof)
		if not plan.ok:
			quote.message=str(plan.message)
			return {}
		for roof_key in plan.add:
			if not sim.allows_public_build(token,cell(roof_key)):
				quote.message=PUBLIC_BUILD_DENIED
				return {}
			var below=sim.state.ground.get(roof_key)
			var roof=plan.add[roof_key]
			if sim.state.roofs.has(roof_key) or not ROOM_ENCLOSURE.is_floor_piece(below):
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
	for site in hanger_sites:
		var tile:=key(site)
		var roof=plan.add.get(tile,sim.state.roofs.get(tile))
		if tile in plan.remove or not ROOF_FIXTURES.supported(roof,token):
			problem_count+=1
			if problems.size()<BLUEPRINT_MAX_PROBLEMS:
				problems.append({"x":site.x,"y":site.y,"kind":ROOF_FIXTURES.HANGING_POT,"reason":ROOF_FIXTURES.SUPPORT_MESSAGE})
	if problem_count>0:
		quote.message=ROOF_FIXTURES.SUPPORT_MESSAGE
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
	var undo_limit:=CONSTRUCTION_HISTORY.MAX_EDGE_BLUEPRINT_BUILDS if includes_edges else CONSTRUCTION_HISTORY.MAX_BLUEPRINT_BUILDS
	if not history.is_empty() and int(history.serial)<CONSTRUCTION_HISTORY.MAX_SERIAL and _undo_utc()>=0.0 and _undo_ticks()>=0 and pieces.size()<=undo_limit:
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
	return {"sim":sim,"cells":cells,"edges":edges,"inventories":staged,"plan":plan,"region":region,"name":str(bp.name),
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
	if kind in RESIDENT_GOALS.DOUBLE_BENCHES:
		var end:=c+(Vector2i.DOWN if settings.get("vertical",false) else Vector2i.RIGHT)
		var space:=PLOT_PERMISSIONS.blueprint_floor(self,token,end,kind)
		if not space.ok:return space.message
	if BLUEPRINT_DESIGN.is_square_piece({"kind":kind,"settings":settings}) or BLUEPRINT_DESIGN.is_wide_bench_piece({"kind":kind,"settings":settings}) or BLUEPRINT_DESIGN.is_mill_piece({"kind":kind,"settings":settings}) or kind in INDUSTRY.ORIENTABLE_FOOTPRINTS:
		for offset:Vector2i in INDUSTRY.station_cells(kind,settings.get("vertical",false)):
			var space:=PLOT_PERMISSIONS.blueprint_floor(self,token,c+offset,kind)
			if not space.ok:return space.message
	var result:=_build_piece(token,c,kind,false,kind in RESIDENT_GOALS.DOUBLE_BENCHES and settings.get("vertical",false),settings.get("wide",false),settings.get("vertical",false),true,int(settings.get("facing",-1)) if kind==INDUSTRY.MILL else -1)
	if not result.ok:return str(result.message)
	if not style.is_empty():state[BUILD_STYLES.expected_layer(kind)][k].style=style
	if kind==INDUSTRY.VINE_ARCH and settings.has("vine_color"):state.objects[k].vine_color=settings.vine_color
	if kind==INDUSTRY.LEAF_MAT and settings.has("leaf_mat_shade"):state.ground[k].leaf_mat_shade=settings.leaf_mat_shade
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
	for edge_id:String in commit.edges:state.edges[edge_id]=sim.state.edges[edge_id].duplicate(true)
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
	_undo_capture(token,region,"blueprint" if commit.edges.is_empty() else "edge_blueprint","藍圖「%s」"%commit.name,before,builds_before)
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
	# C13: any cell of a new 3x3 mill acts on its anchor, the only cell holding the buffers.
	k=_mill_anchor_key(k)
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

## C12 D05 森林菇湯：阿榆的常駐委託。位置、樹與背包都由伺服器判定，不採信客戶端；階段規則在
## forest_mushroom_commission.gd。只寫本人的 player[FOREST_MUSHROOM.KEY]、背包與鈴幣。
func _forest_mushroom_action(player:Dictionary,p:Vector2i,dist:float,extra:String) -> Dictionary:
	if extra not in FOREST_MUSHROOM.EXTRAS:return fail("無法辨識這次林間委託。")
	if _region!=REGIONS.HOME:return fail("林間委託只在家園進行。")
	if not FOREST_MUSHROOM.open(state):return fail(FOREST_MUSHROOM.LOCKED_TEXT)
	var result:Dictionary
	if extra==FOREST_MUSHROOM.SURVEY:
		# 自然樹：不是玩家種的樹（forest 層），也沒被砍掉，並且離公告板夠遠。
		if dist>FOREST_MUSHROOM.REACH or resource(p)!="tree" or state.forest.has(key(p)) or not FOREST_MUSHROOM.forest_cell(p):
			return fail("走到離公告板夠遠、自然生長的樹旁，才能察看林間濕氣。")
		result=FOREST_MUSHROOM.survey(state,player)
	else:
		var spot:=bond_place(state,FOREST_MUSHROOM.RESIDENT)
		if str(spot[0])!=_region or p!=spot[1] or dist>FOREST_MUSHROOM.REACH:return fail("請走到阿榆身邊。")
		result=FOREST_MUSHROOM.accept(state,player) if extra==FOREST_MUSHROOM.ACCEPT else FOREST_MUSHROOM.deliver(state,player)
	return ok(str(result.message)) if result.ok else fail(str(result.message))

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

## C13: the anchor key of a new mill cell; every other key is returned unchanged.
func _mill_anchor_key(k:String) -> String:
	if not INDUSTRY.is_mill_extension(state.objects.get(k,{})):return k
	return key(station_anchor(state.objects,cell(k)))

func process_industry(token:String,k:String,action:String,kind:String) -> Dictionary:
	k=_mill_anchor_key(k)
	var device:Dictionary=state.objects.get(k,{})
	if device.get("type") in INDUSTRY.MANUAL_STATIONS and device.owner==token:return _processing_action(token,device,action,kind)
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
	var catalog:=processing_recipes(str(device.type),true)
	if device.has("processing") and (device.has("job") or device.get("auto_enabled",false)):return fail(PROCESSING_MSG_CORRUPT)
	if action in ["queue_processing","start_processing"]:
		if device.get("auto_enabled",false):return fail("先停用自動加工")
		if not catalog.has(extra):return fail("這台設備不能加工此物品")
		if device.type=="seed_maker" and extra.trim_suffix("_seed") in SEED_MAKER.NURSERY_CROPS:return fail("這種花請帶到田尾花園的留種台。")
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
		if kind=="glass" and device.type=="glass_furnace":
			state.players[token].greenhouse_glass_crafted=true
		if kind=="strawberry_jam":
			_record_discovery(state.players[token],"meals",kind)
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
	if action in ["mine_mud_lure","mine_mud_claim","mine_mud_duel"]:
		return _mine_mud_event(player,action,p,extra)
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
		return ok(REGIONS.arrival_notice(extra))
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
		MEAL_BUFF.refill(player)
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
	if p not in MINES.NODES:return fail("請靠近可開採的礦點。")
	var mining_pick:=active_mining_pick(inv)
	if mining_pick.is_empty():
		if depth+1>MINES.SHALLOW_DEPTH:return fail("深層礦道需要自己的強化石鎬。")
		if not player.get("borrowed_mine_pick",false):return fail("請帶強化石鎬，或到休息站借用公用鎬。")
	if p==MINE_DRILL.NODE and MINE_DRILL.reserved(state.objects):return fail("這個礦點正由採掘機開採。")
	var ready: Dictionary = progress.ready.get(_region,{})
	if float(ready.get(key(p),0.0))>float(state.time):return fail("礦點正在整理。")
	var ore: String = MINES.ORES[depth]
	var quantity: int = MINES.YIELDS[depth]
	if int(inv.get(ore,0))>1000000000-quantity:return fail("背包已滿。")
	var rest := Vector2.ZERO
	var efficiency:Dictionary=MINING_PICK_EFFECTS.get(mining_pick,{})
	var energy_cost:=roundi(MINES.energy_cost(depth+1)*float(efficiency.get("energy",1.0)))
	var strike_now:=float(state.time)
	MEAL_BUFF.expire(player,strike_now)
	var discounted:bool=MEAL_BUFF.has(player,MEAL_BUFF.SALAD,strike_now)
	if MEAL_BUFF.exhausts(player,energy_cost,strike_now):
		rest=safe_arrival(Vector2(MINES.REST)+Vector2(0.5,0.5))
		if rest==Vector2.ZERO:return fail("休息站目前無法抵達。")
	give(inv,ore,quantity)
	# Shallow strata and the deep catalog can supply +1 finds, skipped at the cap.
	var sand_note := ""
	for found:String in MINES.finds(depth+1):
		if int(inv.get(found,0)) >= 1000000000:continue
		give(inv,found,1)
		sand_note += "、%s +1" % NAMES[found]
	ready[key(p)]=float(state.time)+float(efficiency.get("cooldown",MINES.COOLDOWN))
	progress.ready[_region]=ready
	if rest==Vector2.ZERO:MEAL_BUFF.spend(player,energy_cost,strike_now)
	if rest!=Vector2.ZERO:
		player.x=rest.x
		player.y=rest.y
		var had_effect:=not MEAL_BUFF.active_id(player,strike_now).is_empty()
		MEAL_BUFF.recover_from_exhaustion(player)
		var message:="取得%s +%d%s。體力用盡，已回休息站。"%[NAMES[ore],quantity,sand_note]
		if had_effect:message+="餐點效果已結束。"
		var result:=ok(message)
		result.mine_exhausted=true
		return result
	return ok("取得%s +%d%s%s。" % [NAMES[ore],quantity,sand_note,"（沙拉效果 −5%）" if discounted else ""])

func _mine_mud_event(player:Dictionary,action:String,p:Vector2i,extra:String) -> Dictionary:
	if _region!=MINES.MUD_REGION or not state.picnic:return fail("請到第一層礦道的北側洞口。")
	var phase:=int(player.get("mud_alcove",0))
	var inv:Dictionary=player.inventory
	var adventure:bool=state.get("world_mode")=="adventure"
	if action=="mine_mud_duel":
		if not adventure or p!=MINES.MUD_GATE or phase!=0:return fail("這裡無法挑戰小泥團。")
		return _mine_mud_duel(player,extra)
	if not extra.is_empty():return fail("無效的側洞操作。")
	if action=="mine_mud_lure":
		if adventure:return fail("小泥團正準備衝刺，先側移閃避再反擊。")
		if p!=MINES.MUD_GATE or phase!=0:return fail("這裡已經可以通過。")
		var carrot_bait:="radish" if int(inv.get("radish",0))>0 else "quality_radish"
		if int(inv.get(carrot_bait,0))<=0:return fail("帶一顆蘿蔔來，小泥團會跟著香味走。")
		give(inv,carrot_bait,-1)
		player.mud_alcove=1
		return ok("小泥團追著蘿蔔移到旁邊。沿北側洞口進去看看。")
	if p!=MINES.MUD_REWARD or phase!=1 or float(player.y)>=MINES.MUD_ALCOVE_EDGE:return fail("從北側洞口走進去，才能拾取露出的礦料。")
	if int(inv.get("copper_ore",0))>1000000000-MINES.MUD_COPPER:return fail("背包中的銅礦料已達上限。")
	give(inv,"copper_ore",MINES.MUD_COPPER)
	player.mud_alcove=2
	return ok("拾到銅礦料 ×%d。"%MINES.MUD_COPPER)

func _mine_mud_duel(player:Dictionary,choice:String) -> Dictionary:
	var now:=float(state.time)
	var duel:Dictionary=player.get("mud_duel",{})
	var strike_at:=float(duel.get("strike_at",-MINES.MUD_RECOVERY-1.0))
	if choice=="start":
		if now<strike_at+MINES.MUD_RECOVERY:return fail("小泥團還在這一輪挑戰中。")
		player.mud_duel={"strike_at":now+MINES.MUD_WINDUP,"origin_x":player.x,"dodged":false}
		return ok("小泥團正要衝過來！向左或右側移閃避。")
	if choice!="strike":return fail("無效的挑戰操作。")
	if now<strike_at:return fail("等小泥團衝過去，再反擊。")
	if now>=strike_at+MINES.MUD_RECOVERY or not duel.get("dodged",false):
		return fail("這一輪沒抓到時機，等牠停下後可以再試。")
	player.erase("mud_duel")
	player.mud_alcove=1
	return ok("時機正好！小泥團退到了旁邊。")

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

## C11 石工台 recipe `bridge_foundation` (Q05): stone only, deposited straight into the shared
## bridge project (no loose item to lose). Either end of the station crafts; one craft = one point.
func _stone_craft(token:String,player:Dictionary,k:String,extra:String)->Dictionary:
	var station:Dictionary=state.objects.get(k,{})
	if station.get("type")!=INDUSTRY.STONE_WORKBENCH or INDUSTRY.square_part(station)!=0:return fail("到石工台旁選擇配方")
	if state.get("board",false)!=true:return fail(STONE_WORKSHOP.LOCKED_MSG)
	if extra!=STONE_WORKSHOP.FOUNDATION:return fail("石工台沒有這張配方，石地板與小熔爐請直接到建造選單施工")
	if not STONE_WORKSHOP.project_pending(state):return fail(STONE_WORKSHOP.BRIDGE_DONE_MSG)
	if int(state[STONE_WORKSHOP.PROJECT_KEY].get("foundations",0))>=STONE_WORKSHOP.FOUNDATIONS_NEEDED:return fail("橋基已經備齊，還差木材與繩索，到公告板捐。")
	var inv:Dictionary=player.inventory
	var cost:Dictionary=STONE_WORKSHOP.FOUNDATION_COST
	for item in cost:
		if int(inv.get(item,0))<int(cost[item]):return fail("製作材料不足，需要%s %d"%[NAMES[item],int(cost[item])])
	# Validated: from here on nothing can fail. The stone is the foundation (never charged a second time).
	var project:Dictionary=_upgrade_bridge_project()
	for item in cost:give(inv,item,-int(cost[item]))
	project.foundations=int(project.foundations)+1
	player.crafting_points=mini(1000000000,int(player.get("crafting_points",0))+1)
	note_resident_participation(token,"bridge")
	var progress:String="橋基完成（%d／%d）"%[int(project.foundations),STONE_WORKSHOP.FOUNDATIONS_NEEDED]
	if _settle_bridge(project):return ok(progress+"！河灣橋開通了，去東邊看看吧！")
	return ok(progress+"。"+_bridge_remaining_text(project)+"朋友也能接著做。")

## Q05 board donation `bridge_donate`: wood and rope only (the stone is the workbench foundations). Each item takes
## min(missing, carried) so an over-full bag never overfills; nothing changes unless something is given.
func _bridge_donate(token:String,player:Dictionary,p:Vector2i,extra:String)->Dictionary:
	if p!=STONE_WORKSHOP.BOARD_CELL or Vector2(float(player.x),float(player.y)).distance_to(Vector2(p)+Vector2(0.5,0.5))>STONE_WORKSHOP.BOARD_REACH:
		return fail("請到渡口公告板旁捐河灣橋的材料")
	if not extra.is_empty():return fail("無法辨識這次捐贈")
	if state.get("board",false)!=true:return fail(STONE_WORKSHOP.DONATE_WAIT_MSG)
	if not STONE_WORKSHOP.project_pending(state):return fail(STONE_WORKSHOP.BRIDGE_DONE_MSG)
	var inv:Dictionary=player.inventory
	var gift:Dictionary=STONE_WORKSHOP.contribution(state,inv)
	if int(gift.wood)+int(gift.rope)==0:return fail(STONE_WORKSHOP.DONATE_NONE_MSG)
	var project:Dictionary=_upgrade_bridge_project()
	for item:String in ["wood","rope"]:
		if int(gift[item])>0:
			give(inv,item,-int(gift[item]))
			project[item]=int(project[item])+int(gift[item])
	note_resident_participation(token,"bridge")
	var parts:=PackedStringArray()
	if int(gift.wood)>0:parts.append("木材 %d"%int(gift.wood))
	if int(gift.rope)>0:parts.append("繩索 %d"%int(gift.rope))
	var given:="已捐入 "+"、".join(parts)+"。"
	if _settle_bridge(project):return ok(given+"河灣橋開通了，去東邊的橋邊釣魚吧！")
	return ok(given+_bridge_remaining_text(project))

## Lazily turns a pending C11-shaped project into the four-field Q05 shape (foundations kept, wood/rope 0).
func _upgrade_bridge_project()->Dictionary:
	var project:Dictionary=state[STONE_WORKSHOP.PROJECT_KEY]
	if project.size()!=4:
		project=STONE_WORKSHOP.upgraded(project)
		state[STONE_WORKSHOP.PROJECT_KEY]=project
	return project

## Flips `done` exactly once, when all three requirements are met. True when it just opened.
func _settle_bridge(project:Dictionary)->bool:
	if project.get("done",false)==true or not STONE_WORKSHOP.is_complete(project):return false
	project.done=true
	state.events.append("大家備齊了橋基、木材與繩索，河灣橋開通了")
	return true

func _bridge_remaining_text(project:Dictionary)->String:
	var left:PackedStringArray=[]
	var foundations:int=STONE_WORKSHOP.FOUNDATIONS_NEEDED-int(project.get("foundations",0))
	var wood:int=STONE_WORKSHOP.WOOD_NEEDED-int(project.get("wood",0))
	var rope:int=STONE_WORKSHOP.ROPE_NEEDED-int(project.get("rope",0))
	if foundations>0:left.append("橋基 %d"%foundations)
	if wood>0:left.append("木材 %d"%wood)
	if rope>0:left.append("繩索 %d"%rope)
	return "還缺 "+"、".join(left)+"。"

func _finish_bridge()->void:
	state.board=true
	# Legacy worlds keep no project key (bridge open). A world finishing Q03 now still owes Q05.
	if not state.has(STONE_WORKSHOP.PROJECT_KEY):state[STONE_WORKSHOP.PROJECT_KEY]=STONE_WORKSHOP.fresh_project()
	state.events.append("大家修好了公告板，河灣橋工程（木材、繩索與橋基）開始了")

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

func _fox_action(player:Dictionary,action:String,p:Vector2i,dist:float) -> Dictionary:
	var at_site:=_region==Fox.REGION and p==Fox.SITE and dist<=3.2
	var tracks:=int(player.get("fox_tracks",0))
	if action=="fox_track":
		if tracks==0:
			if not at_site:return fail("先到霧竹溪谷找葉耳狐。")
			player.fox_tracks=1
			return ok("葉耳狐停下腳步，好像在請你看看附近的兩處足印。")
		var bit:=int(Fox.TRACKS.get(p,0))
		if _region!=Fox.REGION or dist>3.2 or bit==0:return fail("到足印旁再觀察。")
		if tracks&bit:return fail("這處足印已經記下了。")
		player.fox_tracks=tracks|bit
		return ok("兩處足印都看過了，回去找葉耳狐。" if player.fox_tracks==7 else "記下一處足印，再找找另一處。")
	if action=="fox_adopt":
		if not at_site or tracks!=7:return fail("走完足印小徑，再回霧竹溪谷找葉耳狐。")
	if action=="fox_hint":
		if not player.get(Fox.FIELD,{}).get("following",false) or _region!=REGIONS.HOME:
			return fail("帶葉耳狐回渡口，牠才會指給你看熟悉的海岸採集點。")
		var clues:=Fox.home_clues(get_script(),state)
		if clues.is_empty():return fail("葉耳狐嗅了嗅，海岸的東西還沒重新長出來。")
		player.fox_hint_until=float(state.time)+60.0
		return ok("葉耳狐朝南岸豎起耳朵。打開島嶼地圖可查看採集位置。")
	return Rabbit.act(self,player,action.get_slice("_",1),at_site,Fox.FIELD,Fox.NAME)

func _open_farm_soil(token:String,cells:Array)->void:
	for tile:String in cells:
		state.crops[tile]={"kind":"","growth":0.0,"wet":false,"owner":token}

func _hand_hoe_spread(token:String,center:Vector2i,inventory:Dictionary)->Dictionary:
	if _region!=REGIONS.HOME:return fail("範圍整地只在家園使用。")
	var tool:=gathering_tool_upgrade("hoe",inventory)
	if tool.is_empty():return fail("把銅鋤或更高階的鋤頭放在背包，就能範圍整地。")
	var plan:=TILLER.hand_plan(self,token,center,tool)
	if plan.cells.is_empty():return fail("中央格需是可開墾的空地。")
	_open_farm_soil(token,plan.cells)
	return ok("%s整地 %d 格，可以播種了。"%[NAMES[tool],plan.cells.size()])

# Both the world preview and server use the same cells and permissions.
func hand_water_plan(token:String,center:Vector2i,tool:String)->Dictionary:
	var result:={"cells":[],"skipped":{}}
	var player:Dictionary=state.players.get(token,{})
	if player.is_empty() or _region!=REGIONS.HOME:return result
	var origin:=Vector2(player.x,player.y)
	var center_key:=key(center)
	var center_allowed:=false
	for offset:Vector2i in TILLER.HAND_PATTERNS.get(tool,[]):
		var tile:=center+offset
		var tile_key:=key(tile)
		var plot:Dictionary=state.crops.get(tile_key,{})
		var reason:=""
		if origin.distance_to(Vector2(tile)+Vector2(0.5,0.5))>TILLER.REACH:reason="距離太遠"
		elif not is_land(tile) or water(tile) or protected(tile):reason="公共通道或水域"
		elif not CROPS.has(plot.get("kind","")):reason="沒有作物"
		else:
			var permission:=PLOT_PERMISSIONS.can_water(self,token,plot)
			if not permission.ok:reason=permission.message
		if tile_key==center_key:center_allowed=reason.is_empty()
		if reason.is_empty() and plot.get("wet",false):reason="已經澆水"
		if reason.is_empty():result.cells.append(tile_key)
		else:result.skipped[tile_key]=reason
	if not center_allowed:result.cells.clear()
	return result

func _hand_water_spread(token:String,player:Dictionary,center:Vector2i,inventory:Dictionary)->Dictionary:
	if _region!=REGIONS.HOME:return fail("範圍澆水只在家園使用。")
	var tool:=gathering_tool_upgrade("water",inventory)
	if tool.is_empty():return fail("把銅澆水壺或更高階的澆水壺放在背包，就能範圍澆水。")
	var plan:=hand_water_plan(token,center,tool)
	if plan.cells.is_empty():return fail("請對可澆水的作物使用，範圍內需有乾燥作物。")
	var old_care:=int(player.get("crop_care",0))
	for tile_key:String in plan.cells:
		var plot:Dictionary=state.crops[tile_key]
		_water_plot(player,plot,plot.get("owner","")==token)
	var new_care:=int(player.get("crop_care",0))
	var message:="%s澆水 %d 格。"%[NAMES[tool],plan.cells.size()]
	if new_care>old_care:
		message+="照料 %d／%d。"%[new_care,CROP_CATALOG.CARE_TARGET]
		if new_care==CROP_CATALOG.CARE_TARGET:message+="下次收成會有優良作物。"
	return ok(message)

func hand_harvest_plan(token:String,center:Vector2i,tool:String)->Dictionary:
	return HARVESTER.plan(self,token,center,TILLER.HAND_PATTERNS.get(tool,[]),true)

func _hand_harvest_spread(token:String,player:Dictionary,center:Vector2i)->Dictionary:
	if _region!=REGIONS.HOME:return fail("範圍採收只在家園使用。")
	var tool:=gathering_tool_upgrade("harvest",player.inventory)
	if tool.is_empty():return fail("把升級的採收鐮放在背包，就能範圍採收。")
	var plan:=hand_harvest_plan(token,center,tool)
	if plan.cells.is_empty():return fail("中央格需有你能採收的成熟作物。")
	var gathered:=_harvest_batch(token,player,plan)
	if not gathered.ok:return gathered
	return ok("採收 %d 格 · %s"%[plan.cells.size(),gathered.message])

func _harvest_batch(token:String,player:Dictionary,plan:Dictionary)->Dictionary:
	var guarantee:=has_crop_guarantee(player)
	var yields:Dictionary=plan.yields.duplicate()
	for tile:String in plan.cells:
		var bonus:=quality_crop(state.crops[tile],guarantee)
		if not bonus.is_empty():give(yields,bonus,1)
		guarantee=false
	for kind:String in yields:
		if int(player.inventory.get(kind,0))+int(yields[kind])>1000000000:return fail("收成物品已達上限，請先整理背包")
	if int(player.harvests)+plan.cells.size()>1000000000:return fail("採收紀錄已達上限，這次沒有施工")
	var report:=PackedStringArray()
	for kind:String in yields:report.append("%s +%d"%[NAMES[kind],yields[kind]])
	for tile:String in plan.cells:_harvest_plot(token,player,state.crops[tile],tile)
	return ok("、".join(report))

func hand_seed_plan(token:String,center:Vector2i,tool:String,crop:String)->Dictionary:
	return SEEDER.plan(self,token,center,crop,TILLER.HAND_PATTERNS.get(tool,[]),true)

func _hand_seed_spread(token:String,center:Vector2i,inventory:Dictionary,crop:String)->Dictionary:
	if _region!=REGIONS.HOME:return fail("範圍播種只在家園使用。")
	var tool:=gathering_tool_upgrade("seed",inventory)
	if tool.is_empty():return fail("把升級的撒種袋放在背包，就能範圍播種。")
	if not CROPS.has(crop):return fail("請先選擇作物種子。")
	var plan:=hand_seed_plan(token,center,tool,crop)
	if plan.eligible.is_empty():return fail("中央格需是自己可播種的空田。")
	if plan.cells.is_empty():return fail("這種種子用完了。")
	_plant_planned_seeds(token,inventory,plan.cells,crop)
	return ok("播下%s %d 格 · 使用 %d 粒種子。"%[CROPS[crop].name,plan.cells.size(),plan.cells.size()])

func _plant_planned_seeds(token:String,inventory:Dictionary,cells:Array,crop:String)->void:
	for tile:String in cells:_plant_crop(token,tile,crop)
	give(inventory,crop+"_seed",-cells.size())

func _plant_crop(token:String,tile_key:String,kind:String) -> void:
	var plot:Dictionary=state.crops[tile_key]
	if _region in RESIDENT_GOALS.GROWTH_REGIONS:
		var owner:String=plot.get("owner","")
		var owner_record:Dictionary=state.players.get(owner,{})
		var tracked:Dictionary=owner_record.get(RESIDENT_GOALS.GROWTH_KEY,{})
		if tracked.get("region")==_region and tracked.get("tile")==tile_key:
			owner_record.erase(RESIDENT_GOALS.GROWTH_KEY)
		if owner!=token:plot["other_sown"]=true
		else:plot.erase("other_sown")
	plot.kind=kind
	plot.growth=0.0
	plot.remaining=int(CROPS[kind].get("cycles",1))

static func has_crop_guarantee(player:Dictionary) -> bool:
	return int(player.get("crop_care",0))>=CROP_CATALOG.CARE_TARGET

static func harvest_fertility(crop:Dictionary) -> int:
	var last_kind:=str(crop.get("last_harvest_kind",""))
	var fertility:=int(crop.get("fertility",0))
	if last_kind.is_empty():return fertility
	return clampi(fertility+(-1 if last_kind==crop.kind else 1),0,2)

static func quality_crop(crop:Dictionary,guarantee:bool) -> String:
	return CROP_CATALOG.QUALITY_PREFIX+str(crop.kind) if guarantee or harvest_fertility(crop)>=2 else ""

func _harvest_plot(token:String,player:Dictionary,crop:Dictionary,tile_key:String,box_owner:=false) -> int:
	if greenhouse_covers(tile_key) and not crop_grows_in_season(crop.kind,_region,cell(tile_key),float(state.time)):
		if state.roofs[tile_key].owner==token and (box_owner or crop.get("owner","")==token):
			player.greenhouse_cross_season_crop=crop.kind
	var count:int=CROPS[crop.kind].yield
	give(player.inventory,crop.kind,count)
	var guarantee:=has_crop_guarantee(player)
	var bonus:=quality_crop(crop,guarantee)
	var fertility:=harvest_fertility(crop)
	crop.last_harvest_kind=crop.kind
	crop.fertility=0 if fertility>=2 else fertility
	if not bonus.is_empty():
		give(player.inventory,bonus,1)
		if guarantee:player.crop_care=0
	_record_discovery(player,"crops",crop.kind)
	CHAPTER_ONE.record_harvest(state,token,crop.kind,count)
	player.harvests+=1
	crop["remaining"]=maxi(0,int(crop.get("remaining",1))-1)
	if int(crop.remaining)==0:
		crop.erase("other_sown")
		crop.kind=""
		crop.growth=0.0
	else:crop.growth=regrow_start(str(crop.kind))
	crop.wet=false
	return count

static func luggage_count(items:Dictionary) -> int:
	var count:=0
	for amount in items.values():count+=int(amount)
	return count

static func inn_tea_count(items:Dictionary) -> int:
	return int(items.get(INN_TEA_ITEM,0))+int(items.get(GINGER_TEA,0))

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

static func chest_exact_quantity(value:String) -> int:
	if value.length()>10 or not value.is_valid_int() or value.begins_with("+"):return 0
	var parsed:=int(value)
	return parsed if parsed>0 and parsed<=MINE_FREIGHT.LIMIT else 0

static func ok(message:String) -> Dictionary:
	return {"ok":true,"message":message}

static func fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}

func save() -> bool:
	save_error=""
	if _region != REGIONS.HOME:
		save_error = "Cannot save while a regional projection is active."
		return false
	if save_path.is_empty():return true
	var temporary:=save_path+".tmp"
	var backup:=save_path+".bak"
	var staged_backup:=backup+".staged"
	if DirAccess.dir_exists_absolute(save_path) or DirAccess.dir_exists_absolute(backup) or DirAccess.dir_exists_absolute(staged_backup):
		save_error="Expected a save file, found a directory."
		return false
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:
		save_error="Cannot open temporary save: %s"%FileAccess.get_open_error()
		return false
	var saved:=state.duplicate()
	saved.players=state.players.duplicate()
	for token in saved.players:
		var person:Dictionary=saved.players[token]
		var bench_key:String=person.get(RESIDENT_GOALS.MASTER_BENCH_SEAT,{}).get("cell","")
		var public_seat:bool=person.get("region",REGIONS.HOME)==REGIONS.HOME and RESIDENT_GOALS.aru_public_bench(saved.objects.get(bench_key,{}))
		if not public_seat and not person.has(REGIONS.Springs.REST_SEAT_KEY) and not person.has(TEA_HOUSE_INTERIOR.SEAT_KEY) and not person.has(RESIDENT_GOALS.DIANDIAN_SEAT_KEY):continue
		var standing:=person.duplicate()
		if public_seat:standing.erase(RESIDENT_GOALS.MASTER_BENCH_SEAT)
		standing.erase(REGIONS.Springs.REST_SEAT_KEY)
		standing.erase(TEA_HOUSE_INTERIOR.SEAT_KEY)
		standing.erase(RESIDENT_GOALS.DIANDIAN_SEAT_KEY)
		saved.players[token]=standing
	var written:=file.store_string(JSON.stringify(saved))
	file.flush()
	var err:=file.get_error()
	file.close()
	if not written or err!=OK:
		return _discard_uncommitted_save(temporary,"Cannot write and flush the temporary save: %s"%err)
	# After recovery, keep the known-good backup and retain the damaged original.
	# Normal rotation would otherwise replace the good backup with bad data.
	if recovered_from_backup:
		var quarantined:=""
		if FileAccess.file_exists(save_path):
			quarantined=save_path+".rejected-%d"%Time.get_ticks_usec()
			err=DirAccess.rename_absolute(save_path,quarantined)
			if err!=OK:return _discard_uncommitted_save(temporary,"Cannot quarantine the damaged save: %s"%err)
		err=DirAccess.rename_absolute(temporary,save_path)
		if err!=OK:
			var restore_error:=OK
			if not quarantined.is_empty():restore_error=DirAccess.rename_absolute(quarantined,save_path)
			return _discard_uncommitted_save(temporary,"Cannot publish the recovered save: %s (restore: %s)"%[err,restore_error])
		rejected_path=quarantined
		recovered_from_backup=false
		last_saved_at=int(Time.get_unix_time_from_system())
		return true
	var rotated:=FileAccess.file_exists(save_path)
	if rotated:
		# Windows may remove an existing rename destination before moving its source.
		# Move the primary to an unused name first, so a locked primary leaves the backup intact.
		if FileAccess.file_exists(staged_backup):
			err=DirAccess.rename_absolute(staged_backup,backup)
			if err!=OK:return _discard_uncommitted_save(temporary,"Cannot finish the previous backup rotation: %s"%err)
		err=DirAccess.rename_absolute(save_path,staged_backup)
		if err!=OK:return _discard_uncommitted_save(temporary,"Cannot rotate the previous save: %s"%err)
		err=DirAccess.rename_absolute(staged_backup,backup)
		if err!=OK:
			var restore_error:=DirAccess.rename_absolute(staged_backup,save_path)
			return _discard_uncommitted_save(temporary,"Cannot publish the backup: %s (restore: %s)"%[err,restore_error])
	err=DirAccess.rename_absolute(temporary,save_path)
	if err!=OK:
		var restore_error:=OK
		if rotated:restore_error=DirAccess.rename_absolute(backup,save_path)
		return _discard_uncommitted_save(temporary,"Cannot publish the new save: %s (restore: %s)"%[err,restore_error])
	last_saved_at=int(Time.get_unix_time_from_system())
	return true

func _discard_uncommitted_save(temporary:String,message:String) -> bool:
	save_error=message
	if FileAccess.file_exists(temporary):DirAccess.remove_absolute(temporary)
	return false

func load_world(path:String) -> bool:
	save_path=path
	recovered_from_backup=false
	rejected_path=""
	save_error=""
	last_saved_at=0
	var backup:=path+".bak"
	var staged_backup:=backup+".staged"
	if DirAccess.dir_exists_absolute(path) or DirAccess.dir_exists_absolute(backup) or DirAccess.dir_exists_absolute(staged_backup):
		save_error="Expected a save file, found a directory."
		return false
	var main_exists:=FileAccess.file_exists(path)
	if main_exists and _load_file(path):return true
	var found_save:=main_exists
	for candidate in [staged_backup,backup]:
		if not FileAccess.file_exists(candidate):continue
		found_save=true
		if _load_file(candidate):
			recovered_from_backup=true
			return true
	return not found_save

func _load_file(path:String) -> bool:
	var parser:=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK:return false
	var parsed=parser.data
	if not parsed is Dictionary:return false
	if not preload("res://scripts/save_schema.gd").validate(parsed,CROPS,BUILD,RECIPES,SIZE,TREE_TIME):return false
	state=parsed
	aru_bench={}
	_gather_work.clear()
	CHICKEN_CUDDLE.clear(state.animal) # A restart returns the hen; care cooldown remains.
	state.animal.erase(CHICKEN_FEED_FOLLOW.FIELD)
	COW_CARE.clear(state) # Restart at the feed station, retaining bond and cooldown.
	LOST_CHICKS.step(state,{},Callable()) # Return feed buckets on restart, keeping positions and score.
	PARTY_CART.step(state,{}) # Clear absent crew; a pending segment keeps its safe destination.
	LANTERN_STROLL.step(state,{})
	if not state.has(WARM_SPRINGS.BATH_KEY):
		for person:Dictionary in state.players.values():
			if not RESIDENT_GOALS.done(person,"nuannuan").has(2):continue
			state[WARM_SPRINGS.BATH_KEY]=true
			break
	_region=REGIONS.HOME
	# Monotonic ticks only bind records captured by THIS process and world.
	_undo_ticks_at={}
	_undo_watch_memos.clear()
	_undo_preview_proposal.clear()
	_undo_preview_roof_layers={}
	_undo_preview_roof_problem=""
	_undo_used={}
	return true
