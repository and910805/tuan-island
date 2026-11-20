extends RefCounted

const SMELTER:="small_smelter"
const CLAY_KILN:="clay_kiln"
const DYE_TABLE:="dye_table"
const ASSEMBLY_TABLE:="assembly_table"
const FABRIC_SCREEN:="inn_fabric_screen"
const MUSHROOM_STOOL:="mushroom_cap_stool"
const HEDGEHOG_BASKET:="hedgehog_nap_basket"
const ACORN_CABINET:="acorn_cabinet"
const CABINET_ACCESS:="acorn_cabinet_access"
const CABINET_SLOTS:=16
const SPORE_LAMP:="spore_nightlight"
const PAPER_TEA_LAMP:="paper_tea_lamp"
## Furniture lamps whose owner flips `lamp_off` with the shared floor-lamp action.
const SWITCHABLE_LAMPS:=["lamp",PAPER_TEA_LAMP]
const LEAF_MAT:="leaf_floor_mat"
const BRAIDED_RUG:="braided_round_rug"
const MAT_SHADE_ACTION:="leaf_mat_shade"
const MAT_SHADES:={"light":"淺葉綠","dark":"深苔綠"}
const MUSHROOM_STOOL_FEET:=Vector2(0.5,0.90)
const WOOD_CHAIR:="chair"
const WOOD_CHAIR_BUSY:="矮背木椅有人坐著，等對方起身後再操作。"
const MUSHROOM_STOOL_BUSY:="小菇矮凳上有人，等對方起身後再操作。"
const INDIGO_CUSHION:="indigo_cushion"
const INDIGO_CUSHION_FEET:=Vector2(0.5,0.72)
const INDIGO_CUSHION_BUSY:="靛藍坐墊上有人，等對方起身後再操作。"
const MUSHROOM_TABLE:="mushroom_cap_table"
const BAMBOO_TEA_TABLE:="bamboo_tea_table"
const FOUR_SEAT_TABLES:=[MUSHROOM_TABLE,BAMBOO_TEA_TABLE]
const TEA_TABLE_SNACKS:=["mist_tea_brew","ginger_tea","tea_pudding","garden_cookie","strawberry_toast"]
const TEA_TABLE_SEATS:=[Vector2(1.0,-0.12),Vector2(2.26,0.70),Vector2(1.0,1.42),Vector2(-0.26,0.70)]
const TEA_TABLE_VERTICAL_SEATS:=[Vector2(0.5,-0.15),Vector2(1.23,0.90),Vector2(0.5,2.38),Vector2(-0.23,0.90)]
const TEA_TABLE_FACING:=[Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT]
const MUSHROOM_SIT:="mushroom_table_sit"
const MUSHROOM_SERVE:="mushroom_table_serve"
const MUSHROOM_EAT:="mushroom_table_eat"
const MUSHROOM_TAKE:="mushroom_table_take"
const MUSHROOM_TABLE_CAPACITY:=4
const MUSHROOM_MEAL_ENERGY:=12
const MUSHROOM_SEATS:=[Vector2(0.10,0.90),Vector2(1.90,0.90),Vector2(0.28,1.95),Vector2(1.72,1.95)]
const MUSHROOM_TABLE_BUSY:="還有人在餐桌旁，等大家起身後再操作。"
const HOLLOW_BED:="tree_hollow_bed"
const HOLLOW_REST:="hollow_bed_rest"
const HOLLOW_BUSY:="樹洞裡有人在休息，等對方起身後再操作。"
const INN_BED:="inn_quilt_bed"
const CEDAR_BED:="cedar_bed"
const HOME_REST_FIELD:="home_rest_cell"
const FOOT_BATH:="inn_stone_footbath"
const LUGGAGE_RACK:="inn_luggage_rack"
const QUIET_BIRDHOUSE:="quiet_birdhouse"
const MUSHROOM_POST:="mushroom_door_mailbox"
const LEAF_DESK:="fallen_leaf_desk"
const DESK_DRAFT_ACTION:="save_desk_draft"
const DESK_DRAFT_FIELD:="desk_draft"
const OBSERVATION_DESK:="crop_observation_desk"
const GRID_BOOKCASE:="grid_bookcase"
const SEED_CABINET:="seed_specimen_cabinet"
const NURSERY_BOX=preload("res://scripts/nursery_box.gd").KIND
const GLASS_FLOWER_TABLE:="glass_flower_table"
const VINE_ARCH:="vine_garden_arch"
const FOREST_ARCH:="forest_arch"
const ARCHES:=[VINE_ARCH,FOREST_ARCH]
const POT_RACK:="copper_flower_rack"
const POT_RACK_PUT:="copper_rack_put"
const POT_RACK_TAKE:="copper_rack_take"
const POT_RACK_SLOTS:=3
const POT_RACK_EMPTY:="flower_pot"
const POT_RACK_FLOWERS=preload("res://scripts/flower_nursery.gd").FLOWERS
const VINE_COLOR_ACTION:="vine_arch_color"
const VINE_COLORS:={"pink":"蜜桃粉","cream":"奶油白","lavender":"霧紫"}
const AQUARIUM:="small_aquarium"
const AQUARIUM_FISH:="redfish"
const AQUARIUM_STOCK:="aquarium_stock"
const AQUARIUM_TAKE:="aquarium_take"
const COAST_FISH_COUNTER:="ice_blue_fish_counter"
const COAST_AWNING:="blue_stripe_awning"
const COAST_CART:="xiaoli_market_cart"
const CART_BUSY:="招牌攤車仍在營業，等午夜結算後才能搬移或拆除。"
const COAST_REGISTER:="whitewood_register"
const SHELL_BOTTLES:=["shell_bottle_scallop","shell_bottle_conch","shell_bottle_tide"]
const TABLE_VASE:="table_vase_herb"
const TABLE_VASE_BLOOMS:={TABLE_VASE:"chime_herb","table_vase_bluebell":"bluebell","table_vase_orange":"orange_blossom"}
const TABLE_VASE_SWAP:="table_vase_swap"
## T07 小陶茶具: a tabletop piece, never floor furniture. It rides the existing table display
## paths (regular wood table, rounded table) as one more display item; the bamboo tea table
## keeps it in its own `tea_set` flag so it never counts as, or competes with, meal stock.
const TEA_SET:="small_ceramic_tea_set"
const TEA_SET_COST:={"clay":6,"mist_tea":1}
const TEA_SET_FIELD:="tea_set"
## Pouring emotes only a host that finds a placed tea set near the sender will broadcast.
## They are deliberately NOT part of Session.EMOTES (the generic menu/hotkey list).
const TEA_SET_EMOTES:={"tea_pour":"斟茶～","tea_serve":"奉茶，請用！"}
const TEA_SET_EMOTE_BUTTONS:={"tea_pour":"斟茶","tea_serve":"奉茶"}
const TEA_SET_REACH:=3.2
const WOOD_TABLE_DISPLAY:=SHELL_BOTTLES+[TABLE_VASE,"table_vase_bluebell","table_vase_orange",TEA_SET]
const ROUNDED_TABLE:="rounded_wood_table"
const ROUNDED_EAT:="rounded_table_eat"
const ROUNDED_CAPACITY:=2
const ROUNDED_DECOR:=WOOD_TABLE_DISPLAY+["flower_pot","bluebell","orange_blossom","chime_herb","seashell","gold_sample"]
const SHELL_BOTTLE_COST:={"glass":2,"seashell":3}
const SHELL_TABLE:="shell_round_table"
const SHELL_SIT:="shell_table_sit"
const SHELL_PUT:="shell_table_put"
const SHELL_TAKE:="shell_table_take"
const SHELL_BUSY:="貝殼圓桌還有人坐著，等大家起身後再操作。"
const BEACH_CHAIR:="folding_beach_chair"
const BEACH_SIT:="beach_chair_sit"
const BEACH_FOLD:="beach_chair_fold"
const BEACH_BUSY:="沙灘椅有人使用，等對方起身再操作。"
## T10 竹編躺椅: a 1x2 (rotatable to 2x1) single reclining seat. Reclining only stores the existing
## resident seat pose {cell, side 0}; it restores no energy, never advances the clock, spawns nothing
## and never counts as a bed. Everyone may recline, one at a time; only the owner may move/remove.
const BAMBOO_LOUNGER:="bamboo_lounger"
const LOUNGER_REST:="bamboo_lounger_rest"
const LOUNGER_BUSY:="竹編躺椅有人在休息，等對方起身再操作。"
const LOUNGER_NOT_OWNER:="只有躺椅的主人能搬移或拆除。"
## T08 河岸屏風: a two-tile folding screen shaped like the inn fabric screen. Deployed, both
## tiles block; folded, both tiles pass (see is_folded_passage), so folding can never wall a
## player in. `riverside_screen_folded` lives on every part so the pair always agrees.
const RIVERSIDE_SCREEN:="riverside_screen"
const RIVERSIDE_FOLD:="riverside_screen_fold"
const RIVERSIDE_FOLDED_FIELD:="riverside_screen_folded"
const RIVERSIDE_OCCUPIED:="屏風的占地範圍有人，請先讓開再展開或放置。"
const RIVERSIDE_NOT_OWNER:="只有屏風的主人能收起或展開。"
## Same four foot corners as World.can_stand/UNDO_FOOT: a body overlaps a tile iff a corner is in it.
const FOOT_BOX:=[Vector2(-0.22,-0.17),Vector2(0.22,-0.17),Vector2(-0.22,0.17),Vector2(0.22,0.17)]
const COUNTER_PUT:="fish_counter_put"
const COUNTER_TAKE:="fish_counter_take"
const COUNTER_CAPACITY:=3
## T06 茶葉展示櫃: three display spaces backed by real `items` counts (one unit per space).
## Only tea that is safe to hold in plain inventory: no jars (tea_jar family) and nothing
## from the Maokong packing/shipping record is created or consumed here.
const TEA_DISPLAY_CABINET:="tea_display_cabinet"
const TEA_CABINET_PUT:="tea_cabinet_put"
const TEA_CABINET_TAKE:="tea_cabinet_take"
const TEA_CABINET_SLOTS:=3
const TEA_CABINET_TEAS:=["mist_tea","quality_mist_tea","tea_leaf","tea_light","tea_deep"]
## T11 茶屋點心架: a 1x1 two-tier food shelf. Each tier is an independent real store kept in
## `snack_tiers` (Array of two {item: count} Dictionaries); the generic `items` stays empty so
## nothing is ever counted twice. Only cooked, shareable meals (shareable_meal) may be stored.
## Access reuses the acorn cabinet policy (`cabinet_shared`); only the owner moves/removes it.
const TEA_SNACK_SHELF:="tea_snack_shelf"
const SNACK_PUT:="tea_snack_put"
const SNACK_TAKE:="tea_snack_take"
const SNACK_FIELD:="snack_tiers"
const SNACK_VISUAL_FIELD:="snack_display"
const SNACK_TIER_NAMES:=["上層","下層"]
const SNACK_TIER_KINDS:=3
const SNACK_TIER_LIMIT:=99
const SNACK_REACH:=3.2
const SNACK_REMOVE_MESSAGE:="先取出點心架上的點心，再拆除。"
const SNACK_UNDO_MESSAGE:="點心架上已有點心，先取出才能復原這筆施工。"
## T12 不完美的茶亭: an open, walkable 3x3 shelter (never in World.UNDO_SOLID). Every one of the nine
## cells is a part of one footprint (part index = row-major, 0 = north-west anchor, 4 = centre) so
## move / dismantle / undo / blueprints / save validation reuse the shared multi-tile lifecycle.
## The kind is unlocked by the player's own persisted chacha stage-3 goal (see imperfect_tea_pavilion.gd).
const IMPERFECT_TEA_PAVILION:="imperfect_tea_pavilion"
const PAVILION_INSPECT:="pavilion_inspect"
const PAVILION_REACH:=3.2
const PAVILION_SIZE:=3
const SEED_SAMPLES:="seed_samples"
const SEED_DISPLAY:="seed_cabinet_display"
const SEED_CLEAR:="seed_cabinet_clear"
const SEED_SAMPLE_SLOTS:=3
const LUGGAGE_SLOTS:=2
const FOOT_BATH_SEATS:=[Vector2(0.57,0.67),Vector2(2.43,0.67),Vector2(0.57,1.48),Vector2(2.43,1.48)]
const ANIMAL_COLLECTOR:="animal_collector"
const ANIMAL_COLLECTOR_KIT:="animal_collector_kit"
const COLLECTOR_MATERIALS:={"iron_ingot":6,"woodwork_parts":4,"wood":12}
const TOOL_BOARD=preload("res://scripts/wall_fixtures.gd").TOOL_BOARD
## C11 石工台: a normal 2x1 station (1x2 when a blueprint rotates it) like the dye table. Every
## cell carries `stone_bench_part` (0 = anchor, 1 = far end) [+ `stone_bench_vertical`]; the far
## end is never a second station and never a second refund. Recipes/Q05 live in stone_workshop.gd.
const STONE_WORKBENCH:="stone_workbench"
## C12 公共廚房灶台: a fixed 2x2 stove (like the smelter / clay kiln). The legacy 1x1 `stove` keeps its
## id, recipes and saved queues untouched; this is a separate type whose four cells carry
## `kitchen_stove_part` 0..3 (0 = anchor, row-major). Only the anchor holds `cooking`; the other three
## cells are never a second stove, a second queue or a second refund. Dishes: kitchen_stove.gd.
const KITCHEN_STOVE:="kitchen_stove"
const KITCHEN_STOVE_PART:="kitchen_stove_part"
## C13 麵粉磨坊: the existing `mill` id. A legacy placed mill (built from a `mill_kit`) carries NO `mill_part`
## and stays one cell forever (square_part() == -1 like a legacy bench), so `mill` is deliberately NOT in
## ORIENTABLE_FOOTPRINTS / FIXED_SQUARE_STATIONS. A new mill is a 3x3: cells are row-major (part 0 = north-west
## anchor) and every cell carries `mill_part` 0..8 plus the same `mill_facing` 0..3. Facing 0 puts the entrance
## on the south side, then clockwise: 1 west, 2 north, 3 east. The middle cell of that side (part 7/3/1/5) is the
## one walkable entrance (see is_folded_passage); the other eight cells block. Only the anchor holds the wheat
## buffer, output items, `job`, `processing` and `auto_enabled`: the other eight are never a second machine,
## second queue or second refund. The cell in front of the entrance (MILL_FRONT_OFFSETS) must stay passable.
const MILL:="mill"
const MILL_PART:="mill_part"
const MILL_FACING:="mill_facing"
const MILL_SIZE:=3
const MILL_FACING_COUNT:=4
const MILL_ENTRANCE_PARTS:=[7,3,1,5]
const MILL_FRONT_OFFSETS:=[Vector2i(1,3),Vector2i(-1,1),Vector2i(1,-1),Vector2i(3,1)]
## What a legacy 1x1 mill (placed from a kit, no `mill_part`) costs to place and refunds: exactly one mill_kit.
const LEGACY_MILL_COST:={"name":"麵粉磨坊","mill_kit":1}
const MILL_FRONT_BLOCKED:="磨坊入口前要留一格空地，不能放擋路的東西。"
const MILL_ENTRANCE_BLOCKED:="磨坊入口外那一格要能走，請換個位置或方向。"
const TWO_CELL_STATIONS:=[DYE_TABLE,ASSEMBLY_TABLE,FABRIC_SCREEN,INN_BED,CEDAR_BED,LUGGAGE_RACK,OBSERVATION_DESK,LEAF_DESK,SEED_CABINET,AQUARIUM,GLASS_FLOWER_TABLE,POT_RACK,NURSERY_BOX,COAST_FISH_COUNTER,COAST_REGISTER,ROUNDED_TABLE,GRID_BOOKCASE,BAMBOO_TEA_TABLE,TEA_DISPLAY_CABINET,TOOL_BOARD,RIVERSIDE_SCREEN,STONE_WORKBENCH]
const ORIENTABLE_FOOTPRINTS:=TWO_CELL_STATIONS+[FOOT_BATH,COAST_AWNING,BEACH_CHAIR,BAMBOO_LOUNGER,IMPERFECT_TEA_PAVILION]+ARCHES
const SPRINKLER_KITS:={"sprinkler":"field_sprinkler_kit","medium_sprinkler":"medium_sprinkler_kit","large_sprinkler":"large_sprinkler_kit"}
const STARTER_SPRINKLER_FIELD:="starter_sprinkler_kit"
const DYEABLE_FURNITURE:=["chair","table","sofa","bed",INN_BED]
const FURNITURE_DYES:={"blue_dye":"藍染","orange_dye":"橙染"}
const DYE_REACH:=4
const FIXED_SQUARE_STATIONS:=[SMELTER,CLAY_KILN,COAST_CART,HOLLOW_BED,MUSHROOM_TABLE,LEAF_MAT,BRAIDED_RUG,KITCHEN_STOVE]
const MANUAL_STATIONS:=["seed_maker","loom","glass_furnace",SMELTER,"jam_pot",CLAY_KILN,DYE_TABLE]
const EXPANDABLE_STATIONS:=["loom","glass_furnace"]
const SQUARE_CELLS:=[Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]
## C08 木工台: the existing `bench` id. Legacy 1x1 benches carry NO `workbench_part` field and stay
## one cell forever (square_part() == -1, like an un-expanded loom). New builds are 2x1 and every
## cell carries `workbench_part` (0 = anchor, 1 = far end; `workbench_vertical` for the 1x2 layout).
## It is deliberately NOT in ORIENTABLE_FOOTPRINTS, which would make every legacy bench two cells.
const WORKBENCH:="bench"
const WORKBENCH_PART:="workbench_part"
const WORKBENCH_VERTICAL:="workbench_vertical"
const SMELTER_CELLS:=SQUARE_CELLS
const METAL_RECIPES:=["copper_ingot","iron_ingot"]

static func assembly_items() -> Dictionary:
	var items:=SPRINKLER_KITS.duplicate()
	items[ANIMAL_COLLECTOR]=ANIMAL_COLLECTOR_KIT
	return items

## Both stove kinds: the early single-cell 小石灶 and the 2x2 C12 灶台.
static func is_stove(kind:String) -> bool:
	return kind=="stove" or kind==KITCHEN_STOVE

## True for cells 1..3 of a C12 stove: never a station of their own (resolve to the anchor).
static func is_stove_extension(obj:Dictionary) -> bool:
	return obj.get("type")==KITCHEN_STOVE and square_part(obj)>0

## True for any cell of a new C13 3x3 mill. Legacy 1x1 mills (no `mill_part`) and other kinds are false.
static func is_new_mill(obj:Dictionary) -> bool:
	return obj.get("type")==MILL and square_part(obj)>=0

## True for cells 1..8 of a new mill: never a station of their own (resolve to the anchor).
static func is_mill_extension(obj:Dictionary) -> bool:
	return obj.get("type")==MILL and square_part(obj)>0

static func mill_facing(obj:Dictionary) -> int:
	var facing:Variant=obj.get(MILL_FACING,0)
	return clampi(int(facing),0,MILL_FACING_COUNT-1) if facing is int or facing is float else 0

## Offset (from the anchor) of the walkable entrance cell for a facing 0..3.
static func mill_entrance_offset(facing:int) -> Vector2i:
	return mill_cells()[MILL_ENTRANCE_PARTS[clampi(facing,0,MILL_FACING_COUNT-1)]]

## Offset (from the anchor) of the cell just outside the entrance, which must stay passable.
static func mill_front_offset(facing:int) -> Vector2i:
	return MILL_FRONT_OFFSETS[clampi(facing,0,MILL_FACING_COUNT-1)]

## True for the one walkable entrance cell of a new mill.
static func is_mill_entrance(obj:Dictionary) -> bool:
	return is_new_mill(obj) and square_part(obj)==MILL_ENTRANCE_PARTS[mill_facing(obj)]

## True when `tile` is the cell in front of an entrance of a new mill anchored in `objects` ("x,y" keys).
## `ignore` is an anchor to skip (the mill currently being moved).
static func is_mill_front(objects:Dictionary,tile:Vector2i,ignore:=Vector2i(-1000,-1000)) -> bool:
	for facing in MILL_FACING_COUNT:
		var anchor:Vector2i=tile-MILL_FRONT_OFFSETS[facing]
		if anchor==ignore:continue
		var obj:Variant=objects.get("%d,%d"%[anchor.x,anchor.y])
		if obj is Dictionary and obj.get("type")==MILL and square_part(obj)==0 and mill_facing(obj)==facing:return true
	return false

static func shareable_meal(item:String,recipes:Dictionary) -> bool:
	return recipes.has(item) and item not in ["feed","sugar","strawberry_jam"]

static func four_seat_meal(kind:String,item:String,recipes:Dictionary) -> bool:
	return item in TEA_TABLE_SNACKS if kind==BAMBOO_TEA_TABLE else shareable_meal(item,recipes)

static func tea_table_seats(vertical:bool)->Array:
	return TEA_TABLE_VERTICAL_SEATS if vertical else TEA_TABLE_SEATS

## True when this table object currently displays a small ceramic tea set.
static func has_tea_set(obj:Dictionary) -> bool:
	if obj.get("type")==BAMBOO_TEA_TABLE:return obj.get(TEA_SET_FIELD,false)==true
	return int(obj.get("items",{}).get(TEA_SET,0))>0

static func rounded_table_item(item:String,recipes:Dictionary) -> bool:
	return item in ROUNDED_DECOR or shareable_meal(item,recipes)

static func rounded_table_count(items:Dictionary) -> int:
	var total:=0
	for amount in items.values():total+=int(amount)
	return total

static func rounded_table_slots(items:Dictionary) -> Array[String]:
	var slots:Array[String]=[]
	var ids:=items.keys()
	ids.sort()
	for item:String in ids:
		for count in mini(int(items[item]),ROUNDED_CAPACITY-slots.size()):slots.append(item)
	return slots

static func square_part_field(kind:String) -> String:
	if kind==WORKBENCH:return WORKBENCH_PART
	if kind==MILL:return MILL_PART
	if kind==STONE_WORKBENCH:return "stone_bench_part"
	if kind==KITCHEN_STOVE:return KITCHEN_STOVE_PART
	if kind==BAMBOO_TEA_TABLE:return "bamboo_tea_table_part"
	if kind==TEA_DISPLAY_CABINET:return "tea_cabinet_part"
	if kind==CEDAR_BED:return "cedar_bed_part"
	if kind==MUSHROOM_TABLE:return "mushroom_table_part"
	if kind==LEAF_MAT:return "leaf_mat_part"
	if kind==BRAIDED_RUG:return "braided_rug_part"
	if kind==HOLLOW_BED:return "hollow_bed_part"
	if kind==FOOT_BATH:return "bath_part"
	if kind==LUGGAGE_RACK:return "luggage_part"
	if kind==OBSERVATION_DESK:return "observation_part"
	if kind==LEAF_DESK:return "leaf_desk_part"
	if kind==SEED_CABINET:return "seed_cabinet_part"
	if kind==NURSERY_BOX:return "nursery_box_part"
	if kind==COAST_FISH_COUNTER:return "fish_counter_part"
	if kind==COAST_AWNING:return "awning_part"
	if kind==COAST_CART:return "market_cart_part"
	if kind==COAST_REGISTER:return "register_part"
	if kind==ROUNDED_TABLE:return "rounded_table_part"
	if kind==GRID_BOOKCASE:return "bookcase_part"
	if kind==TOOL_BOARD:return "tool_board_part"
	if kind==BEACH_CHAIR:return "beach_chair_part"
	if kind==BAMBOO_LOUNGER:return "bamboo_lounger_part"
	if kind==IMPERFECT_TEA_PAVILION:return "imperfect_pavilion_part"
	if kind==RIVERSIDE_SCREEN:return "riverside_screen_part"
	if kind==AQUARIUM:return "aquarium_part"
	if kind==GLASS_FLOWER_TABLE:return "glass_table_part"
	if kind==VINE_ARCH:return "vine_arch_part"
	if kind==FOREST_ARCH:return "forest_arch_part"
	if kind==POT_RACK:return "copper_rack_part"
	return {"small_smelter":"smelter_part","loom":"loom_part","glass_furnace":"furnace_part","clay_kiln":"kiln_part","dye_table":"dye_part","assembly_table":"assembly_part",FABRIC_SCREEN:"screen_part",INN_BED:"inn_bed_part"}.get(kind,"")

static func square_part(obj:Dictionary) -> int:
	var kind:String=obj.get("type","")
	if kind==WORKBENCH:
		var part:Variant=obj.get(WORKBENCH_PART,-1)
		return int(part) if part is int or part is float else -1
	if kind==MILL:
		var mill_part:Variant=obj.get(MILL_PART,-1)
		return int(mill_part) if mill_part is int or mill_part is float else -1
	if kind in FIXED_SQUARE_STATIONS or kind in ORIENTABLE_FOOTPRINTS:return int(obj.get(square_part_field(kind),0))
	if kind in EXPANDABLE_STATIONS:return int(obj.get(square_part_field(kind),-1))
	return -1

static func vertical_field(kind:String) -> String:
	if kind==WORKBENCH:return WORKBENCH_VERTICAL
	if kind==STONE_WORKBENCH:return "stone_bench_vertical"
	if kind==BAMBOO_TEA_TABLE:return "bamboo_tea_table_vertical"
	if kind==TEA_DISPLAY_CABINET:return "tea_cabinet_vertical"
	if kind==CEDAR_BED:return "cedar_bed_vertical"
	if kind==FABRIC_SCREEN:return "screen_vertical"
	if kind==INN_BED:return "inn_bed_vertical"
	if kind==FOOT_BATH:return "bath_vertical"
	if kind==LUGGAGE_RACK:return "luggage_vertical"
	if kind==OBSERVATION_DESK:return "observation_vertical"
	if kind==LEAF_DESK:return "leaf_desk_vertical"
	if kind==SEED_CABINET:return "seed_cabinet_vertical"
	if kind==NURSERY_BOX:return "nursery_box_vertical"
	if kind==COAST_FISH_COUNTER:return "fish_counter_vertical"
	if kind==COAST_AWNING:return "awning_vertical"
	if kind==COAST_REGISTER:return "register_vertical"
	if kind==ROUNDED_TABLE:return "rounded_table_vertical"
	if kind==GRID_BOOKCASE:return "bookcase_vertical"
	if kind==TOOL_BOARD:return "tool_board_vertical"
	if kind==BEACH_CHAIR:return "beach_chair_vertical"
	if kind==BAMBOO_LOUNGER:return "bamboo_lounger_vertical"
	if kind==IMPERFECT_TEA_PAVILION:return "imperfect_pavilion_vertical"
	if kind==RIVERSIDE_SCREEN:return "riverside_screen_vertical"
	if kind==AQUARIUM:return "aquarium_vertical"
	if kind==GLASS_FLOWER_TABLE:return "glass_table_vertical"
	if kind==VINE_ARCH:return "vine_arch_vertical"
	if kind==FOREST_ARCH:return "forest_arch_vertical"
	if kind==POT_RACK:return "copper_rack_vertical"
	return "assembly_vertical" if kind==ASSEMBLY_TABLE else "dye_vertical"

static func is_vertical(obj:Dictionary) -> bool:
	return obj.get(vertical_field(obj.get("type","")),false)==true

static func pavilion_cells() -> Array:
	var cells:Array=[]
	for row in PAVILION_SIZE:
		for column in PAVILION_SIZE:cells.append(Vector2i(column,row))
	return cells

## The nine row-major cells of a new C13 mill (same shape as the pavilion).
static func mill_cells() -> Array:
	return pavilion_cells()

## True for a new 2x1 workbench (either end). Legacy 1x1 benches and other kinds are false.
static func is_wide_bench(obj:Dictionary) -> bool:
	return obj.get("type")==WORKBENCH and square_part(obj)>=0

## True only for the far-end filler cell of a wide workbench: never a station of its own.
static func is_bench_extension(obj:Dictionary) -> bool:
	return obj.get("type")==WORKBENCH and square_part(obj)>0

static func station_cells(kind:String,vertical:=false) -> Array:
	if kind==WORKBENCH:return [Vector2i.ZERO,Vector2i.DOWN if vertical else Vector2i.RIGHT]
	if kind==IMPERFECT_TEA_PAVILION or kind==MILL:return pavilion_cells()
	if kind==COAST_AWNING:
		return [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE,Vector2i(0,2),Vector2i(1,2)] if vertical else [Vector2i.ZERO,Vector2i.RIGHT,Vector2i(2,0),Vector2i.DOWN,Vector2i.ONE,Vector2i(2,1)]
	if kind==FOOT_BATH:
		return [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE,Vector2i(0,2),Vector2i(1,2)] if vertical else [Vector2i.ZERO,Vector2i.RIGHT,Vector2i(2,0),Vector2i.DOWN,Vector2i.ONE,Vector2i(2,1)]
	if kind in ARCHES:
		var step:=Vector2i.DOWN if vertical else Vector2i.RIGHT
		return [Vector2i.ZERO,step,step*2]
	if kind in TWO_CELL_STATIONS or kind==BEACH_CHAIR or kind==BAMBOO_LOUNGER:return [Vector2i.ZERO,Vector2i.DOWN if vertical else Vector2i.RIGHT]
	return SQUARE_CELLS

static func is_arch_passage(obj:Dictionary) -> bool:
	var kind:String=obj.get("type","")
	return kind in ARCHES and obj.get(square_part_field(kind))==1

static func is_folded_chair_passage(obj:Dictionary)->bool:
	return obj.get("type")==BEACH_CHAIR and obj.get("beach_chair_part")==1 and obj.get("beach_chair_folded",false)

static func is_folded_screen(obj:Dictionary)->bool:
	return obj.get("type")==RIVERSIDE_SCREEN and obj.get(RIVERSIDE_FOLDED_FIELD,false)==true

## Every tile a player may walk through although its type is in World.UNDO_SOLID: arch
## passages, the folded chair footrest and BOTH tiles of a folded riverside screen.
static func is_folded_passage(obj:Dictionary)->bool:
	return is_arch_passage(obj) or is_folded_chair_passage(obj) or is_folded_screen(obj) or is_mill_entrance(obj)

## True when any foot corner of a body standing at `pos` lies in one of `cells`.
static func foot_box_hits(pos:Vector2,cells:Array)->bool:
	for offset:Vector2 in FOOT_BOX:
		var v:=pos+offset
		if Vector2i(floori(v.x),floori(v.y)) in cells:return true
	return false

static func valid_rack_pots(pots:Variant)->bool:
	if not pots is Array or pots.size()!=POT_RACK_SLOTS or pots.count("")==POT_RACK_SLOTS:return false
	for pot in pots:
		if not pot is String or (pot not in ["",POT_RACK_EMPTY] and pot not in POT_RACK_FLOWERS):return false
	return true

static func counter_fish(obj:Dictionary)->Array:
	var result:Array=obj.get("items",{}).keys()
	result.sort()
	return result

## Units on the cabinet (every unit takes one of the three spaces).
static func tea_cabinet_total(items:Variant)->int:
	var total:=0
	if items is Dictionary:
		for amount in items.values():total+=int(amount)
	return total

## One entry per occupied space, in stable (sorted) order; same tea can repeat.
static func tea_cabinet_slots(items:Variant)->Array[String]:
	var slots:Array[String]=[]
	if not items is Dictionary:return slots
	var ids:Array=items.keys()
	ids.sort()
	for tea:String in ids:
		for count in mini(int(items[tea]),TEA_CABINET_SLOTS-slots.size()):slots.append(tea)
	return slots

static func valid_tea_cabinet_items(items:Variant)->bool:
	if not items is Dictionary:return false
	var total:=0
	for tea in items:
		if not tea is String or tea not in TEA_CABINET_TEAS:return false
		var amount:Variant=items[tea]
		if amount is bool or not (amount is int or (amount is float and is_finite(amount) and floorf(amount)==amount)):return false
		if int(amount)<1 or int(amount)>TEA_CABINET_SLOTS:return false
		total+=int(amount)
	return total<=TEA_CABINET_SLOTS

static func snack_food(item:String,recipes:Dictionary) -> bool:
	return shareable_meal(item,recipes)

static func fresh_snack_tiers() -> Array:
	var tiers:Array=[]
	for tier in SNACK_TIER_NAMES.size():
		var empty:Dictionary={}
		tiers.append(empty)
	return tiers

## The live {item: count} Dictionary of one tier, or a throwaway empty one when absent/malformed.
static func snack_tier(obj:Dictionary,tier:int) -> Dictionary:
	var tiers:Variant=obj.get(SNACK_FIELD)
	if tiers is Array and tier>=0 and tier<tiers.size() and tiers[tier] is Dictionary:
		var live:Dictionary=tiers[tier]
		return live
	return {}

static func snack_tier_total(items:Dictionary) -> int:
	var total:=0
	for amount in items.values():total+=int(amount)
	return total

static func snack_total(obj:Dictionary) -> int:
	var total:=0
	for tier in SNACK_TIER_NAMES.size():total+=snack_tier_total(snack_tier(obj,tier))
	return total

static func snack_ids(items:Dictionary) -> Array[String]:
	var ids:Array[String]=[]
	for item in items:
		if int(items[item])>0:ids.append(str(item))
	ids.sort()
	return ids

## The item drawn on the shelf for a tier: largest stack, ties by id; "" when the tier is empty.
static func snack_lead(obj:Dictionary,tier:int) -> String:
	var items:Dictionary=snack_tier(obj,tier)
	var lead:=""
	for item:String in snack_ids(items):
		if lead.is_empty() or int(items[item])>int(items[lead]):lead=item
	return lead

## "<tier>:<item>:<count>" -> {ok, message, tier, item, count}. Strict: no signs, no padding, 1..limit.
static func parse_snack_request(extra:String) -> Dictionary:
	var bad:Dictionary={"ok":false,"message":"請選擇層架、點心和件數。","tier":-1,"item":"","count":0}
	var parts:PackedStringArray=extra.split(":")
	if parts.size()!=3 or parts[2].length()>3 or not parts[2].is_valid_int() or parts[2].begins_with("+") or parts[2].begins_with("-"):return bad
	if parts[0] not in ["0","1"] or parts[1].is_empty():return bad
	var count:=int(parts[2])
	if str(count)!=parts[2]:return bad
	if count<1 or count>SNACK_TIER_LIMIT:
		bad.message="每次可存取 1 到 %d 份。"%SNACK_TIER_LIMIT
		return bad
	return {"ok":true,"message":"","tier":int(parts[0]),"item":parts[1],"count":count}

static func valid_snack_tiers(tiers:Variant,recipes:Dictionary) -> bool:
	if not tiers is Array or tiers.size()!=SNACK_TIER_NAMES.size():return false
	for entry in tiers:
		if not entry is Dictionary or entry.size()>SNACK_TIER_KINDS:return false
		for item in entry:
			if not item is String or not snack_food(item,recipes):return false
			var amount:Variant=entry[item]
			if amount is bool or not (amount is int or (amount is float and is_finite(amount) and floorf(amount)==amount)):return false
			if int(amount)<1 or int(amount)>SNACK_TIER_LIMIT:return false
	return true

static func uses_station(kind:String,station:String) -> bool:
	return PROCESS.get(kind,{}).get("station","")==station or (station==SMELTER and kind in METAL_RECIPES)

## ── 第 40 章「分流閘」diversion_gate（家園工坊；蘭陽回訪完成後才能製作 diversion_gate_kit）
##   物件：{"type":"diversion_gate","owner","items":{},"mode":"open"|"low"|"closed"}（新放置為 open），
##   和水管一樣不擋路、算在 NETWORK（連接同一位主人的水管）；每人每地區最多 LIMITS.diversion_gate=8。
##   動作 gate_mode（World）：p＝分流閘格，extra＝GATE_MODES 之一；只有主人能切換（同 toggle_pump）。
##   plan() 語意（沒有分流閘的網路走原本的程式路徑，結果完全相同）：在同一個連通網路裡，
##   從所有儲水桶出發做 BFS：
##     R_full＝不經過 low/closed 分流閘能到的格子（open 照常通過）；
##     R_low ＝經過 open/low、但不經過 closed 能到的格子。
##   灑水器／水力加工台：在 R_full 的先照原順序補水；只在 R_low 的接著用剩下的桶水補；
##   只能經過 closed 才到得了的這一輪拿不到水（自己已存的水不動，照常灑水消耗）。
##   桶水仍是整個網路共用一池（依桶的順序取水）；水泵→儲水桶的進水不受分流閘影響
##   （分流閘不隔開水泵和儲水桶）。沒有亂數、不看時鐘。
##   介面用：GATE_MODES、GATE_MODE_NAMES、gate_mode_name(mode)、zone_of(...)、
##   zone_report(state_or_snapshot,gate_key) -> {"ok","mode","consumers":[{"key","type","zone"}]}，
##   zone ∈ ZONE_FULL "full"／ZONE_LOW "low"／ZONE_CUT "cut"。
const GATE_KIND := "diversion_gate"
const GATE_KIT := "diversion_gate_kit"
const GATE_MODES := ["open","low","closed"]
const GATE_MODE_NAMES := {"open":"全開","low":"餘水","closed":"關閉"}
const GATE_ACTION := "gate_mode"
const ZONE_FULL := "full"
const ZONE_LOW := "low"
const ZONE_CUT := "cut"
const GATE_NOT_OWNER := "只能切換自己的分流閘"
const GATE_BAD_MODE := "分流閘只能設為全開、餘水或關閉"
const GATE_SAME_MODE := "分流閘已經是這個設定了"
const GATE_LOCKED := "完成蘭陽回訪的旱日分流後，家園工坊才會開放分流閘。先到宜蘭水圳找星禾。"

## ── 第 40 章「水塔」water_tower（家園工坊；和分流閘同樣在蘭陽回訪完成後才能製作 water_tower_kit）
##   配方（World.CRAFT）：plank 6、copper_joint 2、stone 6 → 1。建造 World.BUILD.water_tower＝{water_tower_kit:1}。
##   物件：{"type":"water_tower","owner","items":{},"water":0..TOWER_CAPACITY,"enabled":bool}
##   （新放置 water 0、enabled true）。和儲水桶一樣擋路（World.UNDO_SOLID、HouseRooms.SOLID_OBJECTS）、
##   算在 NETWORK；每人每地區最多 LIMITS.water_tower=4。拆除／復原放置都退回 kit，存水和儲水桶一樣直接
##   消失；搬移時存水跟著水塔走。
##   動作 tower_toggle（TOWER_ACTION，World）：p＝水塔格，extra 忽略；只有主人能切換（TOWER_NOT_OWNER），
##   翻轉 enabled（true＝出水、false＝只蓄水），回傳訊息「水塔已設為「出水」」／「只蓄水」。
##   plan() 語意：沒有水塔的網路走原本的程式路徑（結果逐位元相同）。有 ≥1 座水塔的網路：
##     1. 水泵照舊只補儲水桶（不直接補水塔）。
##     2. 灑水器／水力加工台照舊由桶水供應（分流閘 full→low，cut 拿不到）。沒有儲水桶但有水塔的
##        網路也會處理（只做第 4 步）。
##     3. 水塔用「剩下的桶水」補水：先補在桶的 full 區的水塔、再補 low 區的；cut 區或網路沒有桶的
##        水塔這一輪拿不到。區域判定同灑水器（_reach，從桶出發不經過不可通行的分流閘）。
##        不論 enabled 與否都會補水。依網路順序（components 的 keys 順序）、從第一個還有水的桶取水。
##     4. 每座 enabled 且有水的水塔（網路順序）接著補「自己區域」裡 enabled、未滿的灑水器／水力加工台
##        （依 sprinklers+waterworks 的順序）。自己區域＝從水塔出發只經過 open 分流閘能到的格子
##        （low 與 closed 都擋住水塔出水）。水塔不補儲水桶，也不補其他水塔。
##     沒有亂數、不看時鐘。plan 結果多了水塔的新水量（和桶一樣只在有變化時出現）；World.step 照常寫入。
##     水量守恆：桶＋水塔＋灑水器／加工台的總水量只會因水泵進水與灑水而改變。
##   介面用（純函式，可用伺服器 state 或客戶端 snapshot）：TOWER_KIND、TOWER_KIT、TOWER_CAPACITY、
##   TOWER_ENABLED_NAMES、tower_enabled_name(enabled)、
##   tower_report(snapshot,tower_key) -> {"ok","water","capacity","enabled","refill_zone":"full"|"low"|"cut"|"none",
##     "tanks":int,"consumers":[{"key","type"}]}（refill_zone "none"＝網路裡沒有儲水桶；consumers＝水塔自己區域
##     裡的灑水器／加工台，依網路順序；ok=false 時其餘欄位為 0/false/""/[]），
##   zone_report(...) 另多 "towers":[{"key","zone"}]（zone＝該水塔的補水區 full/low/cut/none）。
##   networks()/network_info() 多三個鍵：towers（座數）、tower_water、tower_capacity；其餘鍵不變。
const TOWER_KIND := "water_tower"
const TOWER_KIT := "water_tower_kit"
const TOWER_CAPACITY := 96
const TOWER_ACTION := "tower_toggle"
const TOWER_ENABLED_NAMES := {true:"出水", false:"只蓄水"}
const TOWER_NONE := "none"
const TOWER_NOT_OWNER := "只能切換自己的水塔"
const TOWER_LOCKED := "完成蘭陽回訪的旱日分流後，家園工坊才會開放水塔。先到宜蘭水圳找星禾。"

## ── 第 40 章「定量分區配水」：水塔的兩個可省略設定（舊存檔與新放置的水塔都沒有這些欄位，行為不變）
##   reserve（桶水保留）∈ TOWER_RESERVES：這座水塔只取「整個網路的儲水桶合計超過 reserve」的部分。
##     0 或省略＝不保留（原行為）。保留量是各水塔各自的門檻，不是把水鎖住——灑水器照常先用桶水。
##   quota（每日配水）∈ TOWER_QUOTAS：這座水塔每個世界日最多送出 quota 份水給自己這一區。
##     0 或省略＝不限（原行為）。有 quota 時物件另帶 quota_day（世界日，floor(time/TOWER_DAY)）與
##     quota_used（當日已送出，0..TOWER_QUOTA_MAX）；quota 為 0 時三個欄位都不存在。
##     世界日以 plan 當下的 world.state.time 計（跨午夜的那一輪仍算前一日）。
##     當日調低 quota 不會清掉已送出的量（已超過就等隔日）；調成不限再調回會從 0 起算。
##   動作 tower_set（TOWER_SET_ACTION，World）：p＝水塔格，extra＝"reserve:<n>" 或 "quota:<n>"；只有主人。
##     tower_set_apply(tower,extra,day) -> ""（已套用）或拒絕訊息（物件不變）。
##   plan_detail(world,pump_rate) -> {"water":{…同 plan()…},"quota":{tower_key:{"day","used"}}}；
##     quota 只列出本輪有送水、quota_day／quota_used 要更新的水塔。plan() 仍只回傳 water。
##   tower_report(snapshot,key,day=-1) 另多 "reserve"、"quota"、"quota_used"（當日；day<0 時用 snapshot.time 算）、
##     "quota_left"（不限為 -1）。
const TOWER_SET_ACTION := "tower_set"
const TOWER_RESERVES := [0,12,24,36,48]
const TOWER_QUOTAS := [0,4,8,16,24]
const TOWER_QUOTA_MAX := 24
const TOWER_DAY := 1440.0
const TOWER_BAD_SETTING := "水塔設定只能選面板上的數值"
const TOWER_SAME_SETTING := "水塔已經是這個設定了"

const INTERVAL := 8.0
const TANK_CAPACITY := 48
const PUMP_RATE := 8
const LIMITS := {"water_pipe":128,"water_tank":8,"water_pump":4,"diversion_gate":8,"water_tower":4}
const SPRINKLER_CAPACITIES := {"sprinkler":12,"medium_sprinkler":24,"large_sprinkler":48}
const SPRINKLER_LIMIT := 16

static func sprinkler_offsets(kind:String) -> Array[Vector2i]:
	var offsets:Array[Vector2i]=[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
	if kind in ["medium_sprinkler","large_sprinkler"]:
		offsets.append_array([Vector2i(-1,-1),Vector2i(1,-1),Vector2i(1,1),Vector2i(-1,1)])
	if kind=="large_sprinkler":
		for y in range(-2,3):
			for x in range(-2,3):
				if maxi(absi(x),absi(y))==2:offsets.append(Vector2i(x,y))
	return offsets

const NETWORK := ["water_pipe","water_tank","water_pump","sprinkler","medium_sprinkler","large_sprinkler","waterworks","diversion_gate","water_tower"]
const NEIGHBORS := [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
const PROCESS := {
	"orange_dye":{"station":DYE_TABLE,"ingredients":{"orange_blossom":3},"time":30.0,"yield":2},
	"blue_dye":{"station":DYE_TABLE,"ingredients":{"bluebell":3},"time":30.0,"yield":2},
	"fired_brick":{"station":CLAY_KILN,"ingredients":{"clay":3,"charcoal":1},"time":75.0,"yield":2},
	"flower_pot":{"station":CLAY_KILN,"ingredients":{"clay":4,"charcoal":1},"time":60.0,"yield":1},
	# C16 磚瓦: a tile batch is priced exactly like a brick batch (same clay, fuel, time, yield);
	# one tile roofs one cell (World.BUILD terracotta_roof). Id = TerracottaRoof.TILE.
	"roof_tile":{"station":CLAY_KILN,"ingredients":{"clay":3,"charcoal":1},"time":75.0,"yield":2},
	"cotton_cloth":{"station":"loom","ingredients":{"cotton":3},"time":60.0,"yield":1},
	"wool_cloth":{"station":"loom","ingredients":{"wool":2},"time":60.0,"yield":1},
	# T067 glass furnace (owner-only manual queue like the loom, never automated).
	# "glass" here is the furnace recipe R17; the workbench CRAFT.glass recipe is a
	# separate table (World.CRAFT) and stays unchanged.
	"glass":{"station":"glass_furnace","ingredients":{"crystal_sand":3,"wood":1},"time":120.0,"yield":1},
	"crystal_sand":{"station":"glass_furnace","ingredients":{"vein_quartz":2},"time":60.0,"yield":3},
	"iron_ingot":{"station":"glass_furnace","ingredients":{"iron_ore":2,"charcoal":1},"time":60.0,"yield":2},
	"copper_ingot":{"station":"glass_furnace","ingredients":{"copper_ore":2,"charcoal":1},"time":45.0,"yield":2},
	"plank":{"station":"sawmill","ingredients":{"wood":4},"time":12.0,"yield":2},
	"charcoal":{"station":"charcoal_kiln","ingredients":{"wood":4},"time":16.0,"yield":2},
	"flour":{"station":"mill","ingredients":{"wheat":2},"time":60.0,"yield":1},
	"feed":{"station":"mill","ingredients":{"sweet_corn":1,"fiber":2},"time":60.0,"yield":4},
	"strawberry_jam":{"station":"jam_pot","ingredients":{"strawberry":3,"sugar":1},"time":180.0,"yield":2},
}

static func near_river(world, tile:Vector2i) -> bool:
	for x in range(-2,3):
		for y in range(-2,3):
			var offset:=Vector2i(x,y)
			var target:=tile+offset
			if world._region=="home" and preload("res://scripts/wangan_coast.gd").STAR_POOL.has_point(target):continue
			if absi(x)+absi(y)<=2 and world.is_land(target) and world.water(target):
				return true
	return false

static func components(state:Dictionary) -> Array[Dictionary]:
	var objects:Dictionary=state.get("objects",{})
	var seen:Dictionary={}
	var result:Array[Dictionary]=[]
	for start in objects:
		if seen.has(start) or objects[start].type not in NETWORK:continue
		var group:Dictionary={"keys":[],"tanks":[],"pumps":[],"sprinklers":[],"waterworks":[]}
		var queue:Array[String]=[start]
		seen[start]=true
		var owner:String=objects[start].owner
		var index:=0
		while index<queue.size():
			var key:=queue[index]
			index+=1
			group["keys"].append(key)
			match objects[key].type:
				"water_tank":group.tanks.append(key)
				"sprinkler","medium_sprinkler","large_sprinkler":group.sprinklers.append(key)
				"waterworks":group.waterworks.append(key)
				"water_pump":group.pumps.append(key)
			var parts:=key.split(",")
			var cell:=Vector2i(int(parts[0]),int(parts[1]))
			for offset in NEIGHBORS:
				var next:Vector2i=cell+offset
				var neighbor:="%d,%d"%[next.x,next.y]
				if seen.has(neighbor) or not objects.has(neighbor):continue
				var other:Dictionary=objects[neighbor]
				if other.owner!=owner or other.type not in NETWORK:continue
				seen[neighbor]=true
				queue.append(neighbor)
		result.append(group)
	return result

static func networks(state:Dictionary) -> Dictionary:
	var result:Dictionary={}
	var objects:Dictionary=state.get("objects",{})
	var day:=tower_day(float(state.get("time",0.0)))
	for group in components(state):
		var towers:=_towers(objects,group)
		var info:Dictionary={"connected_tanks":group.tanks.size(),"connected_pumps":group.pumps.size(),
			"enabled_pumps":0,"water":0,"capacity":group.tanks.size()*TANK_CAPACITY,
			"towers":towers.size(),"tower_water":0,"tower_capacity":towers.size()*TOWER_CAPACITY}
		for pump in group.pumps:
			if objects[pump].enabled:info.enabled_pumps+=1
		for tank in group.tanks:info.water+=int(objects[tank].water)
		for tower in towers:info.tower_water+=int(objects[tower].get("water",0))
		var full:Dictionary={}
		var low:Dictionary={}
		var wet:Dictionary={}
		var classify_supply:=false
		var outlets:=towers.filter(func(key):return objects[key].get("enabled",false))
		var wet_outlets:=outlets.filter(func(key):
			var tower:Dictionary=objects[key]
			var quota:=tower_quota(tower)
			return int(tower.get("water",0))>0 and (quota==0 or tower_quota_used(tower,day)<quota))
		var has_gate:=_has_gate(objects,group)
		if has_gate:
			var wet_tanks:Array=group.tanks.filter(func(key):return int(objects[key].water)>0)
			wet=_reach_from(objects,group,wet_tanks,["open","low"])
			wet.merge(_reach_from(objects,group,wet_outlets,["open"]))
			classify_supply=not group.tanks.is_empty() or not outlets.is_empty()
			if classify_supply:
				var tower_reach:=_reach_from(objects,group,outlets,["open"])
				full=_reach(objects,group,["open"])
				low=_reach(objects,group,["open","low"])
				full.merge(tower_reach)
		for key in group["keys"]:
			result[key]=info
			var is_pipe:bool=objects[key].type=="water_pipe"
			var show_zone:bool=classify_supply and not full.has(key) and (is_pipe or key in group.sprinklers or key in group.waterworks)
			if not is_pipe and not show_zone:continue
			var detail:=info.duplicate()
			if is_pipe:detail.flow_visible=wet.has(key) if has_gate else int(info.water)>0 or not wet_outlets.is_empty()
			if show_zone:detail.supply_zone=ZONE_LOW if low.has(key) else ZONE_CUT
			result[key]=detail
	return result

static func network_info(state:Dictionary,key:String) -> Dictionary:
	return networks(state).get(key,{"connected_tanks":0,"connected_pumps":0,"enabled_pumps":0,"water":0,"capacity":0,"towers":0,"tower_water":0,"tower_capacity":0})

static func pipe_caption(mask:int,info:Dictionary) -> String:
	if mask==0:return "水管 · 未接通"
	var capacity:=int(info.get("capacity",0))+int(info.get("tower_capacity",0))
	if capacity==0:return "水管 · 未接水桶或水塔"
	match info.get("supply_zone",""):
		ZONE_CUT:return "水管 · 分流閘隔開供水"
		ZONE_LOW:return "水管 · 分流閘僅通餘水"
	var stored:=int(info.get("water",0))+int(info.get("tower_water",0))
	if stored==0:return "水管 · 蓄水已空"
	return "水管 · 管網蓄水 %d／%d"%[stored,capacity]

static func supply_note(info:Dictionary) -> String:
	match info.get("supply_zone",""):
		ZONE_CUT:return "此處被分流閘隔開"
		ZONE_LOW:return "此處只接收餘水"
	return ""

static func sprinkler_status(device:Dictionary,now:float) -> String:
	if not device.get("enabled",false):return "已停止"
	var pending:=float(device.get("next_water",0.0))>now
	if pending and device.get("sprinkler_daily",false):return "今日已澆水"
	if int(device.get("water",0))<=0:return "等待補水"
	if pending:return "等待下一輪"
	return "等待澆水"

static func plan(world, pump_rate: int = PUMP_RATE) -> Dictionary:
	return plan_detail(world,pump_rate).water

static func plan_detail(world, pump_rate: int = PUMP_RATE) -> Dictionary:
	var objects:Dictionary=world.state.objects
	var water:Dictionary={}
	var quota:Dictionary={}
	var day:=tower_day(float(world.state.get("time",0.0)))
	for group in components(world.state):
		var tanks:Array=group.tanks
		# Water towers (chapter 40): a tower-free network keeps the exact original path.
		var towers:=_towers(objects,group)
		if tanks.is_empty() and towers.is_empty():continue
		var consumers:Array=group.sprinklers+group.waterworks
		# Diversion gates (chapter 40): only networks that contain a gate are reordered;
		# a gate-free network keeps the exact original consumer order.
		if _has_gate(objects,group):consumers=gated_consumers(objects,group)
		var pumps:=0
		for pump in group.pumps:
			if objects[pump].enabled and near_river(world,world.cell(pump)):pumps+=1
		var incoming:=pumps*pump_rate
		for tank in tanks:
			var existing:=int(objects[tank].water)
			var accepted:=mini(incoming,TANK_CAPACITY-existing)
			water[tank]=existing+accepted
			incoming-=accepted
		var tank_index:=0
		for sprinkler in consumers:
			if not objects[sprinkler].enabled:continue
			var current:=int(objects[sprinkler].water)
			var supplied:=current
			var capacity:int=world.WATERWORKS.CAPACITY if objects[sprinkler].type=="waterworks" else SPRINKLER_CAPACITIES[objects[sprinkler].type]
			while supplied<capacity and tank_index<tanks.size():
				var tank:String=tanks[tank_index]
				var amount:=mini(int(water[tank]),capacity-supplied)
				water[tank]-=amount
				supplied+=amount
				if int(water[tank])==0:tank_index+=1
			if supplied!=current:water[sprinkler]=supplied
		if not towers.is_empty():_tower_round(world,objects,group,towers,water,quota,day)
	for key in water.keys():
		if int(water[key])==int(objects[key].water):water.erase(key)
	return {"water":water,"quota":quota}

# ------------------------------------------------------------ diversion gates --

static func gate_mode_name(mode:String) -> String:
	return str(GATE_MODE_NAMES.get(mode,""))

static func _gate_mode(obj:Dictionary) -> String:
	var mode:=str(obj.get("mode","open"))
	return mode if mode in GATE_MODES else "open"

static func _has_gate(objects:Dictionary,group:Dictionary) -> bool:
	for key in group["keys"]:
		if objects[key].get("type")==GATE_KIND:return true
	return false

## Cells of `group` reachable from its tanks; a gate cell is entered only when its
## mode is in `passable` (tanks themselves are always sources).
static func _reach(objects:Dictionary,group:Dictionary,passable:Array) -> Dictionary:
	return _reach_from(objects,group,group.tanks,passable)

## Same BFS as _reach from arbitrary member cells `sources` (used for a water
## tower's own outflow zone).
static func _reach_from(objects:Dictionary,group:Dictionary,sources:Array,passable:Array) -> Dictionary:
	var members:={}
	for key in group["keys"]:members[key]=true
	var seen:={}
	var queue:Array=[]
	for source in sources:
		seen[source]=true
		queue.append(source)
	var index:=0
	while index<queue.size():
		var key:String=queue[index]
		index+=1
		var parts:=key.split(",")
		var cell:=Vector2i(int(parts[0]),int(parts[1]))
		for offset in NEIGHBORS:
			var next:Vector2i=cell+offset
			var neighbor:="%d,%d"%[next.x,next.y]
			if seen.has(neighbor) or not members.has(neighbor):continue
			var other:Dictionary=objects[neighbor]
			if other.get("type")==GATE_KIND and _gate_mode(other) not in passable:continue
			seen[neighbor]=true
			queue.append(neighbor)
	return seen

## Zone of every consumer (sprinkler/waterworks) of `group`: ZONE_FULL, ZONE_LOW or ZONE_CUT.
static func zone_of(objects:Dictionary,group:Dictionary) -> Dictionary:
	var full:=_reach(objects,group,["open"])
	var low:=_reach(objects,group,["open","low"])
	var out:={}
	for key in group.sprinklers+group.waterworks:
		out[key]=ZONE_FULL if full.has(key) else (ZONE_LOW if low.has(key) else ZONE_CUT)
	return out

## Supply order for a gated network: full-zone consumers in their original order,
## then low-zone consumers; cut consumers are omitted (they receive nothing).
static func gated_consumers(objects:Dictionary,group:Dictionary) -> Array:
	var zones:=zone_of(objects,group)
	var ordered:=[]
	for zone in [ZONE_FULL,ZONE_LOW]:
		for key in group.sprinklers+group.waterworks:
			if zones[key]==zone:ordered.append(key)
	return ordered

## UI helper: per-consumer status of the network containing `gate_key` (works on the
## server state or a client snapshot; owners only need to compare equal).
## {"ok":false} when gate_key is not a diversion gate.
static func zone_report(snapshot:Dictionary,gate_key:String) -> Dictionary:
	var objects:Variant=snapshot.get("objects",{})
	if not objects is Dictionary or not objects.get(gate_key) is Dictionary or objects[gate_key].get("type")!=GATE_KIND:return {"ok":false,"mode":"","consumers":[],"tanks":0,"towers":[]}
	for group in components(snapshot):
		if gate_key not in group["keys"]:continue
		var zones:=zone_of(objects,group)
		var rows:=[]
		for key in group.sprinklers+group.waterworks:
			rows.append({"key":key,"type":str(objects[key].type),"zone":str(zones[key])})
		var tower_zones:=tower_refill_zones(objects,group)
		var tower_rows:=[]
		for tower in _towers(objects,group):tower_rows.append({"key":tower,"zone":str(tower_zones[tower])})
		return {"ok":true,"mode":_gate_mode(objects[gate_key]),"consumers":rows,"tanks":group.tanks.size(),"towers":tower_rows}
	return {"ok":false,"mode":"","consumers":[],"tanks":0,"towers":[]}

# ---------------------------------------------------------------- water towers --

static func tower_enabled_name(enabled:bool) -> String:
	return str(TOWER_ENABLED_NAMES[enabled])

## Tower keys of `group` in network (BFS) order.
static func _towers(objects:Dictionary,group:Dictionary) -> Array:
	var out:=[]
	for key in group["keys"]:
		if objects[key].get("type")==TOWER_KIND:out.append(key)
	return out

## Refill zone of every tower of `group`: ZONE_FULL / ZONE_LOW / ZONE_CUT as seen from
## the tanks (same rule as consumers), or TOWER_NONE when the network has no tank.
static func tower_refill_zones(objects:Dictionary,group:Dictionary) -> Dictionary:
	var out:={}
	var towers:=_towers(objects,group)
	if group.tanks.is_empty():
		for tower in towers:out[tower]=TOWER_NONE
		return out
	var full:=_reach(objects,group,["open"])
	var low:=_reach(objects,group,["open","low"])
	for tower in towers:
		out[tower]=ZONE_FULL if full.has(tower) else (ZONE_LOW if low.has(tower) else ZONE_CUT)
	return out

## Consumers (sprinklers, then waterworks, in network order) a tower can feed: reachable
## from the tower crossing only `open` gates.
static func tower_consumers(objects:Dictionary,group:Dictionary,tower_key:String) -> Array:
	var zone:=_reach_from(objects,group,[tower_key],["open"])
	var out:=[]
	for key in group.sprinklers+group.waterworks:
		if zone.has(key):out.append(key)
	return out

static func _consumer_capacity(world,obj:Dictionary) -> int:
	return world.WATERWORKS.CAPACITY if obj.type=="waterworks" else SPRINKLER_CAPACITIES[obj.type]

## Steps 3 and 4 of a tower network (see header); mutates `water` in place. Tank values
## in `water` are already set by the tank step when the network has tanks.
## `quota` collects {tower:{"day","used"}} for towers whose daily record changes this round.
static func _tower_round(world,objects:Dictionary,group:Dictionary,towers:Array,water:Dictionary,quota:Dictionary={},day:int=0) -> void:
	var zones:=tower_refill_zones(objects,group)
	for tower in towers:water[tower]=int(objects[tower].get("water",0))
	# 3. Refill from the tank water left over: full-zone towers first, then low-zone.
	#    A tower with a reserve only takes what the tanks hold above that total.
	for zone in [ZONE_FULL,ZONE_LOW]:
		for tower in towers:
			if zones[tower]!=zone:continue
			var allowance:=-tower_reserve(objects[tower])
			for tank in group.tanks:allowance+=int(water[tank])
			for tank in group.tanks:
				var room:=mini(TOWER_CAPACITY-int(water[tower]),allowance)
				if room<=0:break
				var amount:=mini(int(water[tank]),room)
				if amount<=0:continue
				water[tank]=int(water[tank])-amount
				water[tower]=int(water[tower])+amount
				allowance-=amount
	# 4. Enabled towers discharge into their own (open-gate-only) zone, at most
	#    `quota` per world day when the owner set one.
	for tower in towers:
		if objects[tower].get("enabled",false)!=true:continue
		var limit:=tower_quota(objects[tower])
		var used:=tower_quota_used(objects[tower],day)
		var sent:=0
		for consumer in tower_consumers(objects,group,tower):
			if int(water[tower])<=0:break
			if limit>0 and used+sent>=limit:break
			var device:Dictionary=objects[consumer]
			if not device.enabled:continue
			var capacity:=_consumer_capacity(world,device)
			var current:=int(water.get(consumer,device.water))
			var amount:=mini(int(water[tower]),capacity-current)
			if limit>0:amount=mini(amount,limit-used-sent)
			if amount<=0:continue
			water[tower]=int(water[tower])-amount
			water[consumer]=current+amount
			sent+=amount
		if limit>0 and sent>0:quota[tower]={"day":day,"used":used+sent}

static func tower_day(time:float) -> int:
	return int(floor(time/TOWER_DAY))

static func _tower_option(tower:Dictionary,field:String,options:Array) -> int:
	var value:Variant=tower.get(field,0)
	if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or float(value)!=floorf(float(value)):return 0
	return int(value) if int(value) in options else 0

static func tower_reserve(tower:Dictionary) -> int:
	return _tower_option(tower,"reserve",TOWER_RESERVES)

static func tower_quota(tower:Dictionary) -> int:
	return _tower_option(tower,"quota",TOWER_QUOTAS)

## Water this tower already sent on world day `day` (0 when its record is from another day).
static func tower_quota_used(tower:Dictionary,day:int) -> int:
	if tower_quota(tower)<=0:return 0
	var stored:Variant=tower.get("quota_day",-1)
	var used:Variant=tower.get("quota_used",0)
	if typeof(stored) not in [TYPE_INT,TYPE_FLOAT] or typeof(used) not in [TYPE_INT,TYPE_FLOAT]:return 0
	return clampi(int(used),0,TOWER_QUOTA_MAX) if int(stored)==day else 0

## Applies one owner setting ("reserve:<n>" / "quota:<n>") to `tower` in place.
## Returns "" when applied, otherwise the refusal message (tower untouched).
static func tower_set_apply(tower:Dictionary,extra:String,day:int) -> String:
	var parts:=extra.split(":")
	if parts.size()!=2 or not parts[1].is_valid_int() or parts[1]!=str(int(parts[1])):return TOWER_BAD_SETTING
	var value:=int(parts[1])
	if parts[0]=="reserve":
		if value not in TOWER_RESERVES:return TOWER_BAD_SETTING
		if tower_reserve(tower)==value:return TOWER_SAME_SETTING
		if value==0:tower.erase("reserve")
		else:tower["reserve"]=value
		return ""
	if parts[0]=="quota":
		if value not in TOWER_QUOTAS:return TOWER_BAD_SETTING
		if tower_quota(tower)==value:return TOWER_SAME_SETTING
		if value==0:
			tower.erase("quota")
			tower.erase("quota_day")
			tower.erase("quota_used")
		else:
			var used:=tower_quota_used(tower,day)
			tower["quota"]=value
			tower["quota_day"]=day
			tower["quota_used"]=used
		return ""
	return TOWER_BAD_SETTING

## Success message for an extra that tower_set_apply accepted.
static func tower_set_message(extra:String) -> String:
	var parts:=extra.split(":")
	var value:=int(parts[1])
	if parts[0]=="reserve":return "水塔已設為「不保留桶水」" if value==0 else "水塔已設為「儲水桶留 %d 份」"%value
	return "水塔已設為「每日配水不限」" if value==0 else "水塔已設為「每日配水 %d 份」"%value

## UI helper for one tower (server state or client snapshot). See header for fields.
static func tower_report(snapshot:Dictionary,tower_key:String,day:int=-1) -> Dictionary:
	var empty:={"ok":false,"water":0,"capacity":0,"enabled":false,"refill_zone":"","tanks":0,"consumers":[],"reserve":0,"quota":0,"quota_used":0,"quota_left":-1}
	var objects:Variant=snapshot.get("objects",{})
	if not objects is Dictionary or not objects.get(tower_key) is Dictionary or objects[tower_key].get("type")!=TOWER_KIND:return empty
	for group in components(snapshot):
		if tower_key not in group["keys"]:continue
		var rows:=[]
		for key in tower_consumers(objects,group,tower_key):rows.append({"key":key,"type":str(objects[key].type)})
		var tower:Dictionary=objects[tower_key]
		var time_value:Variant=snapshot.get("time",0.0)
		var report_day:=day if day>=0 else tower_day(float(time_value) if typeof(time_value) in [TYPE_INT,TYPE_FLOAT] else 0.0)
		var quota_value:=tower_quota(tower)
		var quota_used:=tower_quota_used(tower,report_day)
		return {"ok":true,"water":int(tower.get("water",0)),"capacity":TOWER_CAPACITY,"enabled":tower.get("enabled",false)==true,
			"refill_zone":str(tower_refill_zones(objects,group)[tower_key]),"tanks":group.tanks.size(),"consumers":rows,
			"reserve":tower_reserve(tower),"quota":quota_value,"quota_used":quota_used,
			"quota_left":(maxi(0,quota_value-quota_used) if quota_value>0 else -1)}
	return empty
