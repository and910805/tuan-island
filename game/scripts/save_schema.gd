extends RefCounted
const MUSHROOM_MAIL=preload("res://scripts/mushroom_mail.gd")
const ISLAND_NOTES=preload("res://scripts/island_notes.gd")
const MealBuff=preload("res://scripts/meal_buff.gd")
const OutlyingCommissions=preload("res://scripts/outlying_commissions.gd")
const IslandStoryRecap=preload("res://scripts/island_story_recap.gd")
const ResidentBond=preload("res://scripts/resident_bond.gd")
const BUILD_STYLES = preload("res://scripts/build_style_catalog.gd")
const BARK_FRAME = preload("res://scripts/bark_frame.gd")
const WALL_FIXTURES = preload("res://scripts/wall_fixtures.gd")
const POSTCARDS = preload("res://scripts/travel_postcards.gd")
const OAR_SIGN = preload("res://scripts/oar_sign.gd")
const ROOF_FIXTURES = preload("res://scripts/roof_fixtures.gd")
const WELCOME_SIGN = preload("res://scripts/welcome_sign.gd")
const CHEST_HISTORY = preload("res://scripts/chest_history.gd")
const SPRING_GARDEN = preload("res://scripts/spring_garden_day.gd")
const SEA_BREEZE_FAIR = preload("res://scripts/sea_breeze_fair.gd")
const AUTUMN_FEAST = preload("res://scripts/autumn_feast.gd")
const LANTERN_STROLL = preload("res://scripts/lantern_stroll.gd")
const WARM_LANTERN_NIGHT = preload("res://scripts/warm_lantern_night.gd")
const BEACH_TREASURE = preload("res://scripts/beach_treasure.gd")
const LOST_CHICKS = preload("res://scripts/lost_chicks.gd")
const COOKING_RELAY = preload("res://scripts/cooking_relay.gd")

const MineDrill=preload("res://scripts/mine_drill.gd")
const Waterworks=preload("res://scripts/waterworks.gd")
const StationLife=preload("res://scripts/station_life.gd")
const Bobo=preload("res://scripts/bobo_workshop.gd")
const AutoFreight=preload("res://scripts/mine_auto_freight.gd")
const Freight=preload("res://scripts/mine_freight.gd")
const Mines=preload("res://scripts/mine_depths.gd")
const Survey=preload("res://scripts/mine_survey.gd")
const TeaCeramics=preload("res://scripts/tea_ceramics.gd")
const Jinguashi=preload("res://scripts/jinguashi.gd")
const HistoryMemory=preload("res://scripts/history_memory.gd")
const LanyangLife=preload("res://scripts/lanyang_life.gd")
const Transit=preload("res://scripts/transit.gd")
const Regions=preload("res://scripts/regions.gd")
const Community=preload("res://scripts/community.gd")
const ChapterOne=preload("res://scripts/chapter_one.gd")
const Collections=preload("res://scripts/collections.gd")
const AnimalCollector=preload("res://scripts/animal_collector.gd")
const Weather=preload("res://scripts/weather.gd")
const Industry=preload("res://scripts/industry.gd")
## C11 optional root `bridge_project` (no version bump; absent = legacy/complete, see stone_workshop.gd).
const StoneWorkshop=preload("res://scripts/stone_workshop.gd")
const Forestry=preload("res://scripts/forestry.gd")
const Logistics=preload("res://scripts/logistics.gd")
const ConstructionHistory=preload("res://scripts/construction_history.gd")
const RoomEnclosure=preload("res://scripts/room_enclosure.gd")
const CookingQueue=preload("res://scripts/cooking_queue.gd")
const FlowerNursery=preload("res://scripts/flower_nursery.gd")
const SaltPan=preload("res://scripts/salt_pan.gd")
const OrderCatalog=preload("res://scripts/order_catalog.gd")
## No cycle: item_catalog.gd preloads nothing and reads World.NAMES via load().
const ItemCatalog=preload("res://scripts/item_catalog.gd")
const EdgeGrid=preload("res://scripts/edge_grid.gd")
## 27: persistent edge layer (C02-C04). Every layer (home = top level, plus every
## region) carries `edges`: sparse {edge_key:row}. Keys are canonical
## EdgeGrid.decode(key,size) keys; rows are exactly {"type":"edge_wall"|"edge_window",
## "owner"} or {"type":"edge_door","owner","open":bool}, owner a live player token.
## Older saves get an empty `edges` on the top level and on every stored region
## (old tile objects untouched). Empty placeholders from a current-world fixture
## are accepted, while prior versions with edge rows are rejected.
## 26: chapter 4 Beimen cooperative salt pans. New region "beimen" (appended to
## Regions.ALL), items sea_salt/salt_wheel_kit/salt_rake_kit/salt_grilled_fish,
## recipe salt_grilled_fish and the required root `salt_pan` (SaltPan.valid,
## which also checks the beimen object layer). Older saves get a fresh beimen
## region (before the region-count check) and SaltPan.fresh() only; every older
## field is kept byte-identical. An older save CARRYING any salt id, beimen or
## the salt_pan root is unknown forward state and rejected (never stripped).
## 25: chapter 3 Tianwei cooperative flower nursery. New region "tianwei"
## (appended to Regions.ALL), new crops bluebell/orange_blossom/chime_herb (+ their
## seeds), items blue_dye/sugar, recipe garden_cookie, and the required root
## `flower_nursery` {players, garden} (FlowerNursery.valid). Older saves get a
## fresh tianwei region and FlowerNursery.fresh() only; every older field is kept
## byte-identical. An older save CARRYING any flower id, tianwei or the
## flower_nursery root is unknown forward state and rejected (never stripped).
## 24: Q05 bakery. New object type "mill" (Logistics processor, buffer field
## `input_wheat`, output buffer only "flour", optional `processing` queue of
## Industry.PROCESS mill recipes), new crop "pumpkin" and stove recipe
## "pumpkin_pie". Purely additive: older saves need no migration and are never
## rewritten; an older save CARRYING any of these (mill object, input_wheat,
## pumpkin crop/seed record/collection, pumpkin_pie job/queue/collection) is
## unknown forward state and rejected. Legacy sawmill/kiln keep `input_wood`.
## 23: required root `public_kitchen` {stove,seats,meals,opened} (T042). Older
## saves WITHOUT it get public_kitchen_fresh() only (never an implicit
## registration); an older save CARRYING it is unknown forward state, rejected.
## 22: optional lazy material-source identity `box_id` (exactly 32 lowercase hex)
## on chest/private_chest only, unique across every live layer (home + regions).
## No migration: older chests/history stay byte-identical until World assigns
## an id through an explicit prepare_material_box.
## 21: optional sawmill/charcoal_kiln `processing` queue (CookingQueue canonical
## shape, Industry.PROCESS recipes filtered to the station type).
## 20: optional stove `cooking` queue state (CookingQueue canonical shape).
## 19: construction history action "blueprint" (builds 1..768). Migration
## cutoffs below are literal and must NOT follow VERSION (edges <27, salt <26, flowers <25, bakery <24,
## public kitchen <23, material box id <22, processing queue <21, cooking queue
## <20, blueprint history <19, undo history <18, auto roofs <17).
const VERSION:=27
const EDGE_VERSION:=27
const EDGE_TYPES:=["edge_wall","edge_door","edge_window"]
const EGG_BASKET_CAPACITY:=6
const BLUEPRINT_HISTORY_VERSION:=19
const COOKING_QUEUE_VERSION:=20
const PROCESSING_QUEUE_VERSION:=21
const MATERIAL_SOURCE_VERSION:=22
const PUBLIC_KITCHEN_VERSION:=23
const BAKERY_VERSION:=24
const FLOWER_VERSION:=25
const SALT_VERSION:=26
## Ids that only exist from save 24 on (see bakery_ok).
const BAKERY_STATIONS:=["mill"]
const BAKERY_CROPS:=["pumpkin"]
const BAKERY_RECIPES:=["pumpkin_pie"]
## Exact public_kitchen key set and per-meal requirement (= inclusive cap).
const KITCHEN_KEYS:=["stove","seats","meals","opened"]
const KITCHEN_MEALS:={"soup":4,"bread":2,"salad":2}
## C12/D04 pre-mill flour at Xiaoli's stall. Per-account, optional player field
## `flour_stall`={"day":world day index,"bought":0..FLOUR_STALL_DAILY}; absent in every older save
## (= nothing bought yet). Stock resets when the world day changes (World.flour_left()).
const FLOUR_STALL_KEY:="flour_stall"
const FLOUR_STALL_DAILY:=4
const FLOUR_STALL_PRICE:=64
## 內容設定集 §11 early sugar at the same stall. Per-account optional player field
## `sugar_stall`={"day":world day index,"bought":0..SUGAR_STALL_DAILY}; absent in every older save
## (= nothing bought yet). Resets when the world day changes (World.sugar_left()). Independent of the
## 田尾 market's own `sugar_day`/`sugar_bought` record.
const SUGAR_STALL_KEY:="sugar_stall"
const SUGAR_STALL_DAILY:=2
const SUGAR_STALL_PRICE:=72
const KITCHEN_SEAT_COUNT:=2
## Euclidean tile distances (inclusive), compared squared on integer cells.
const KITCHEN_STOVE_RANGE:=8
const KITCHEN_SEAT_RANGE:=3
const KITCHEN_STOVE_TYPE:="stove"
const KITCHEN_SEAT_TYPE:="long_bench"
const SeedMaker=preload("res://scripts/seed_maker.gd")
## T067 glass_furnace (no save bump): owner-only manual queue exactly like the
## loom (same version-26 rule, never `job`/`auto_enabled`/buffer items).
const PROCESSING_STATIONS:=["sawmill","charcoal_kiln","mill"]+Industry.MANUAL_STATIONS
const BOX_TYPES:=["chest","private_chest"]
const BOX_ID_LENGTH:=32

# Validate the parsed candidate before replacing a live world. Additive defaults
# migrate older prototype saves; invalid nested records never reach game code.
static func nursery_slots_valid(slots:Variant,crops:Dictionary)->bool:
	if not slots is Dictionary or slots.is_empty():return false
	for id in slots:
		if id not in ["0","1","2","3"]:return false
		var crop=slots[id]
		if not crop is Dictionary or not crop.get("kind") is String or not crop.get("wet") is bool:return false
		for field in crop:
			if field not in ["kind","wet","growth","remaining","last_care_day","last_harvest_kind","fertility"]:return false
		if crop.kind!="" and not crops.has(crop.kind):return false
		var max_growth:=0.0 if crop.kind=="" else float(crops[crop.kind].time)
		var cycles:=0 if crop.kind=="" else int(crops[crop.kind].get("cycles",1))
		if not number(crop.get("growth"),0,max_growth) or not whole(crop.get("remaining"),cycles):return false
		if crop.kind=="":
			if crop.wet:return false
		elif int(crop.remaining)<1:return false
		if crop.has("last_care_day") and not whole(crop.last_care_day):return false
		if crop.has("fertility") and not whole(crop.fertility,1):return false
		if crop.has("last_harvest_kind") and (not crop.last_harvest_kind is String or not crops.has(crop.last_harvest_kind)):return false
	return true

static func number(value,minimum:float=0.0,maximum:float=1000000000000.0) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum

static func whole(value,maximum:float=1000000000.0) -> bool:
	return number(value,0,maximum) and floorf(float(value))==float(value)

## T055 optional player.orders.active ({order_id:{"accepted","due"}}). Legacy
## books without "active" stay valid unchanged. When present: catalog ids only,
## exactly the two numeric fields, accepted not after the saved world time and
## a deadline window of at most OrderCatalog.DEADLINE_DAYS world days (1 s
## slack for JSON float round-trips). Overdue entries are valid; World expires
## them lazily without penalty.
static func orders_active_valid(orders:Dictionary,now:float) -> bool:
	if not orders.has("active"):return true
	var active=orders.active
	if not active is Dictionary or active.size()>OrderCatalog.VILLAGE.ORDERS.size():return false
	var window:=float(OrderCatalog.DEADLINE_DAYS)*float(OrderCatalog.VILLAGE.DAY)+1.0
	for id in active:
		if not id is String or OrderCatalog.find(id).is_empty():return false
		var entry=active[id]
		if not entry is Dictionary or entry.size()!=2:return false
		if not number(entry.get("accepted"),0.0,now+1.0) or not number(entry.get("due")):return false
		var span:=float(entry.due)-float(entry.accepted)
		if span<=0.0 or span>window:return false
		entry.accepted=float(entry.accepted)
		entry.due=float(entry.due)
	return true

## T013: every item-count dictionary (player inventory, object/chest items, job
## ingredients) is checked against ItemCatalog's per-item limit. Unknown legacy
## String keys keep the 1,000,000,000 ceiling. An invalid shipped catalog fails
## closed: counts() rejects before touching the dictionary.
static func counts(value) -> bool:
	if not value is Dictionary:return false
	if not ItemCatalog.current().ok:return false
	for item in value:
		if not item is String or item.length()>64 or not whole(value[item],float(ItemCatalog.saved_count_limit(item))):return false
		value[item]=int(value[item])
	return true

static func owner(value) -> bool:
	return value is String and not value.is_empty() and value.length()<=64

static func location(value,size:Vector2i) -> bool:
	if not value is String:return false
	var parts:PackedStringArray=value.split(",")
	if parts.size()!=2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():return false
	var x:=int(parts[0]);var y:=int(parts[1])
	return x>=0 and y>=0 and x<size.x and y<size.y and value=="%d,%d"%[x,y]

static func valid_outlying_commissions(s:Dictionary) -> bool:
	var root:Variant=s.outlying_commissions
	if not root is Dictionary or root.size()!=1 or not root.get("players") is Dictionary:return false
	for token in root.players:
		if not s.players.has(token):return false
		var entries:Variant=root.players[token]
		if not entries is Dictionary or entries.size()>OutlyingCommissions.DEFS.size():return false
		for id in entries:
			var entry:Variant=entries[id]
			if not OutlyingCommissions.DEFS.has(id) or not entry is Dictionary or entry.size()!=1:return false
			if not entry.get("done") is bool or not entry.done:return false
	return true

const GATHER_ITEMS := ["wood","fiber","sapling","resin","hardwood","stone",Regions.Bamboo.ITEM]

static func valid_woodland_stock(state:Dictionary,size:Vector2i)->bool:
	var rules=preload("res://scripts/woodland_stock.gd")
	var stock=state.get(rules.KEY)
	var removed=state.get("removed")
	if not stock is Dictionary or stock.size()!=3 or not stock.get("stumps") is Dictionary or not removed is Dictionary:return false
	var cycle:int=rules.cycle_at(float(state.time))
	if not whole(stock.get("cycle"),cycle) or not whole(stock.get("grown"),rules.TREES_PER_CYCLE):return false
	if stock.stumps.size()>rules.GROVE.size.x*rules.GROVE.size.y:return false
	for tile in stock.stumps:
		if not location(tile,size) or removed.get(tile)!=true:return false
		var axis:PackedStringArray=tile.split(",")
		if not rules.GROVE.has_point(Vector2i(int(axis[0]),int(axis[1]))):return false
		if not whole(stock.stumps[tile],cycle+1) or int(stock.stumps[tile])<1:return false
	return true

static func valid_gather_drops(value:Variant,size:Vector2i,now:float,players:Dictionary) -> bool:
	if not value is Dictionary:return false
	for region in value:
		if region not in Regions.ALL or not value[region] is Dictionary:return false
		for tile in value[region]:
			if not location(tile,size):return false
			var drop:Variant=value[region][tile]
			if not drop is Dictionary or drop.size() not in [2,4] or not number(drop.get("ready_at"),0,now+1.0):return false
			var items:Variant=drop.get("items")
			if not items is Dictionary or items.is_empty():return false
			for item in items:
				if item not in GATHER_ITEMS or not whole(items[item],float(ItemCatalog.saved_count_limit(item))) or items[item]<=0:return false
				if item==Regions.Bamboo.ITEM:
					if region!=Regions.Bamboo.REGION:return false
					if not Regions.Bamboo.CLUMPS.any(func(cell:Vector2i):return Regions.Bamboo.clump_key(cell)==tile):return false
			if drop.size()==4:
				var owner:Variant=drop.get("reserved_for")
				var reserved:Variant=drop.get("reserved")
				if not owner is String or not players.has(owner) or not reserved is Dictionary or reserved.is_empty():return false
				for item in reserved:
					if not items.has(item) or not whole(reserved[item],float(items[item])) or reserved[item]<=0:return false
	return true

static func validate(s:Dictionary,crops:Dictionary,build:Dictionary,recipes:Dictionary,size:Vector2i,tree_time:float) -> bool:
	var version = s.get("version",0)
	if not whole(version,VERSION) or version < 1:return false
	if s.has(Regions.Springs.BATH_KEY) and not s[Regions.Springs.BATH_KEY] is bool:return false
	if version == 1:
		if s.has("regions"):return false
		s.regions = {Regions.LANYANG:Regions.fresh()}
	if not s.get("regions") is Dictionary:return false
	# Version 27: add the empty edge layers FIRST, before any region is touched
	# below (the pre-current deep-mine check reads every Regions.LAYERS field, and
	# the later region-size check counts `edges`). Regions created further down by
	# Regions.fresh() already carry their own empty layer. A version-1 region was
	# just created fresh above. An older save may only carry empty placeholders.
	if int(version)<EDGE_VERSION:
		if not s.get("edges",{}) is Dictionary or not s.get("edges",{}).is_empty():return false
		s.edges={}
		if version!=1:
			for region in s.regions:
				var stored=s.regions[region]
				if not stored is Dictionary or not stored.get("edges",{}) is Dictionary or not stored.get("edges",{}).is_empty():return false
			for region in s.regions:s.regions[region].edges={}
	# T067 deep floors B6–B15 have no save version of their own. A pre-current save
	# may only carry them as untouched empty layers; drop those before the
	# historical region-count checks and re-add them below.
	if int(version)<SALT_VERSION:
		for region in Regions.DEEP_MINES:
			if not s.regions.has(region):continue
			var layer=s.regions[region]
			if not layer is Dictionary:return false
			for field in Regions.LAYERS:
				# Tick bookkeeping (next_*) may advance on an untouched layer.
				if not field.begins_with("next_") and (not layer.get(field) is Dictionary or not layer[field].is_empty()):return false
			s.regions.erase(region)
	if version < 5:
		if s.regions.size() != 1 or not s.regions.has(Regions.LANYANG):return false
		s.regions[Regions.JINGUASHI] = Regions.fresh()
		s.jinguashi = {"ready":{}}
	if version < 6:
		if s.regions.size()!=2:return false
		for region in Mines.IDS.slice(0,Mines.SHALLOW_DEPTH):s.regions[region]=Regions.fresh()
		s.mine_depths=Mines.fresh()
	if version < 9:
		var existing_tea_regions:=0
		for region in Transit.TEA_STOPS:
			if s.regions.has(region):existing_tea_regions+=1
		if s.regions.size()-existing_tea_regions!=7:return false
		for region in Transit.LOCAL:s.regions[region]=Regions.fresh()
	if version<15:
		for region in Transit.TEA_STOPS:
			if not s.regions.has(region):s.regions[region]=Regions.fresh()
	# Version 25: an older save never had the Tianwei region; carrying one is
	# forward state. Add the fresh region before the region-count check.
	if int(version)<FLOWER_VERSION:
		if s.regions.has(FlowerNursery.REGION):return false
		s.regions[FlowerNursery.REGION]=Regions.fresh()
	# Version 26: an older save never had the Beimen region; carrying one is
	# forward state. Add the fresh region before the region-count check.
	if int(version)<SALT_VERSION:
		if s.regions.has(SaltPan.REGION):return false
		s.regions[SaltPan.REGION]=Regions.fresh()
	# Older worlds load an empty layer for new angling reserves.
	for region in Regions.ANGLING_RESERVES:
		if not s.regions.has(region):s.regions[region]=Regions.fresh()
	# T067 deep floors B6–B15 (no version bump): they start empty and can only be
	# entered after mine_depths.unlocked passes 5, which Mines.valid checks below.
	for region in Regions.DEEP_MINES:
		if not s.regions.has(region):s.regions[region]=Regions.fresh()
	if not s.regions.has(Regions.Cart.REGION):s.regions[Regions.Cart.REGION]=Regions.fresh()
	if s.regions.get(Regions.Cart.REGION)!=Regions.fresh():return false
	if s.regions.size() != Regions.ALL.size()-1:return false
	if version<8:
		if not s.has("bobo_workshop"):
			var chosen:Dictionary=Bobo.sites(s)
			s.bobo_workshop=Bobo.fresh()
			s.bobo_workshop.site=Bobo.SITE_PAIRS.find([chosen.npc,chosen.table])
		var players = s.get("players")
		if players is Dictionary:
			for person in players.values():
				if person is Dictionary and person.get("stories") is Dictionary and not person.stories.has("bobo"):person.stories.bobo=0
	if not validate_region(s,crops,build,recipes,size,tree_time):return false
	for token:String in s.players:
		var person:Dictionary=s.players[token]
		if not person.has(Industry.HOME_REST_FIELD):continue
		var rest_cell:Variant=person[Industry.HOME_REST_FIELD]
		if not rest_cell is String:return false
		var rest_bed:Dictionary=s.objects.get(rest_cell,{})
		if rest_bed.get("type")!=Industry.CEDAR_BED or rest_bed.get("owner")!=token or Industry.square_part(rest_bed)!=0:return false
	var active_carts:Dictionary={}
	for cart:Dictionary in s.objects.values():
		if not cart.has("market_cart_open"):continue
		if active_carts.has(cart.owner) or not s.players.get(cart.owner,{}).get("market",{}).get("pending",false):return false
		active_carts[cart.owner]=true
	var resident_goals:=preload("res://scripts/resident_goals.gd")
	var garden_seats:Dictionary={}
	for person:Dictionary in s.players.values():
		var seat:Dictionary=person.get(resident_goals.MASTER_BENCH_SEAT,{})
		if not seat.is_empty():
			var region:String=person.get("region","home")
			var objects:Dictionary=s.objects if region=="home" else s.get("regions",{}).get(region,{}).get("objects",{})
			var bench:Dictionary=objects.get(seat.cell,{})
			if bench.get("type")==Industry.FOOT_BATH:
				if Industry.square_part(bench)!=0 or region!="home":return false
			elif bench.get("type")==Industry.BEACH_CHAIR:
				var seat_id:=region+":"+str(seat.cell)
				if Industry.square_part(bench)!=0 or bench.get("beach_chair_folded",false) or int(seat.side)!=0 or garden_seats.has(seat_id):return false
				garden_seats[seat_id]=true
			elif bench.get("type")==Industry.BAMBOO_LOUNGER:
				var seat_id:=region+":"+str(seat.cell)
				if Industry.square_part(bench)!=0 or int(seat.side)!=0 or garden_seats.has(seat_id):return false
				garden_seats[seat_id]=true
			elif bench.get("type")==Industry.HOLLOW_BED:
				var seat_id:=region+":"+str(seat.cell)
				if Industry.square_part(bench)!=0 or int(seat.side)!=0 or garden_seats.has(seat_id):return false
				garden_seats[seat_id]=true
			elif bench.get("type") in [Industry.SHELL_TABLE]+Industry.FOUR_SEAT_TABLES:
				var seat_id:="%s:%s:%d"%[region,seat.cell,int(seat.side)]
				var seats:=4 if bench.type in Industry.FOUR_SEAT_TABLES else 2
				if int(seat.side)>=seats or Industry.square_part(bench)>0 or garden_seats.has(seat_id):return false
				garden_seats[seat_id]=true
			elif bench.get("type") in [resident_goals.GARDEN_CHAIR,Industry.MUSHROOM_STOOL,Industry.WOOD_CHAIR,Industry.INDIGO_CUSHION]:
				var seat_id:=region+":"+str(seat.cell)
				if int(seat.side)!=0 or garden_seats.has(seat_id):return false
				garden_seats[seat_id]=true
			elif resident_goals.aru_public_bench(bench):
				if region!="home" or int(seat.side)>=resident_goals.ARU_PARK_SEAT_X.size():return false
			elif bench.get("type") not in resident_goals.DOUBLE_BENCHES or bench.get("bench_end",false) or int(seat.side)>1:return false
			if bench.type in resident_goals.INDEPENDENT_TWO_SEATS or resident_goals.aru_public_bench(bench):
				var seat_id:="%s:%s:%d"%[region,seat.cell,int(seat.side)]
				if garden_seats.has(seat_id):return false
				garden_seats[seat_id]=true
			if bench.type==resident_goals.MASTER_BENCH and region!="home":return false
	if not resident_goals.valid_mural(s):return false
	if s.has(resident_goals.GARDEN_KEY):
		var pots=s[resident_goals.GARDEN_KEY]
		if not pots is Array or pots.is_empty() or pots.size()>resident_goals.GARDEN_POTS.size():return false
		var authors:Dictionary={}
		for pot in pots:
			if not pot is Dictionary or pot.size()!=3 or not pot.get("npc") is bool or not pot.get("author") is String or pot.get("flower") not in resident_goals.GARDEN_FLOWERS:return false
			if pot.npc:
				if not resident_goals.GARDEN_NPCS.has(pot.author) or resident_goals.GARDEN_NPCS[pot.author].flower!=pot.flower:return false
			elif not s.players.has(pot.author):return false
			var author_key:="%s:%s"%[pot.npc,pot.author]
			if authors.has(author_key):return false
			authors[author_key]=true
	if s.has(resident_goals.DOCK_LIGHT) and (not s[resident_goals.DOCK_LIGHT] is bool or not s[resident_goals.DOCK_LIGHT] or int(s.get("dock_stage",0))<2):return false
	if s.has(resident_goals.SHEEP_PLAY_KEY):
		var play=s[resident_goals.SHEEP_PLAY_KEY]
		if not play is Dictionary or play.size()!=2 or not resident_goals.SHEEP_TOYS.has(play.get("toy")) or not number(play.get("at"),0,float(s.time)):return false
	if not valid_gather_drops(s.get("gather_drops",{}),size,float(s.time),s.players):return false
	if s.has("woodland_stock") and not valid_woodland_stock(s,size):return false
	if not Regions.Bamboo.valid(s):return false
	if not ISLAND_NOTES.valid(s.get("island_notes",[]),float(s.time)):return false
	if s.has("island_note_revision") and (not whole(s.island_note_revision,ISLAND_NOTES.REVISION_LIMIT) or int(s.island_note_revision)<s.get("island_notes",[]).size()):return false
	if not s.get("players") is Dictionary:return false
	for person in s.get("players",{}).values():
		if person is Dictionary and person.has("island_note_seen") and not whole(person.island_note_seen,ISLAND_NOTES.revision(s)):return false
	if not ISLAND_NOTES.valid(s.get(resident_goals.TREE_NOTES,[]),float(s.time)):return false
	if s.has("dock_stage") and not whole(s.dock_stage,2):return false
	if s.has("world_mode") and s.world_mode!="adventure":return false
	if s.has("dock_project_started") and (not s.dock_project_started is bool or not s.dock_project_started):return false
	if s.has("outlying_commissions") and not valid_outlying_commissions(s):return false
	if s.has("festival_story_open") and not s.festival_story_open is bool:return false
	# T071 豐收接力（不升版）：state.harvest_relay 與 player.harvest_relay 都可省略；
	# 存在時由 HarvestRelay.valid 檢查型別、上限、模型菜種類與一致性。
	if not preload("res://scripts/harvest_relay.gd").valid(s):return false
	# T071 河岸釣魚會（不升版）：state.fish_meet 與 player.fish_meet 都可省略；
	# 存在時由 FishingMeet.valid 檢查型別、上限、魚種序列與一致性。
	if not preload("res://scripts/fishing_meet.gd").valid(s):return false
	# T071 家園布置題（不升版）：state.showcase 與 player.showcase 都可省略；
	# 存在時由 Showcase.valid 檢查型別、上限、主題／道具種類、地塊範圍與一致性。
	if not preload("res://scripts/showcase.gd").valid(s):return false
	if not AUTUMN_FEAST.valid(s):return false
	if not WARM_LANTERN_NIGHT.valid(s):return false
	if not BEACH_TREASURE.valid(s):return false
	if not COOKING_RELAY.valid(s):return false
	if not LOST_CHICKS.valid(s):return false
	if not LANTERN_STROLL.valid(s):return false
	if not Regions.Cart.valid(s):return false
	# T071 紀念票兌換裝飾（不升版）：player.souvenir 可省略；存在時由 SouvenirExchange.valid
	# 檢查型別、已知兌換品、spent＝兌換次數×價目、且不超過三個活動已驗好的累計紀念票。
	if not preload("res://scripts/souvenir_exchange.gd").valid(s):return false
	# T067 Q07 (no version bump): pre-hoist saves lack mine_depths.hoist; deep
	# mines already opened (unlocked >= 6) keep a working surface hoist.
	Mines.migrate(s.get("mine_depths"))
	if not Mines.valid(s):return false
	for person in s.players.values():
		if person is Dictionary and person.has("outlying_boat_arrival") and not person.outlying_boat_arrival is bool:return false
		if version == 1:
			person.region = Regions.HOME
			person.travel_epoch = 0
		if person.get("region") not in Regions.ALL or not whole(person.get("travel_epoch")):return false
		if version < 9:
			if person.region in Transit.LOCAL:return false
			person.travel_book=Transit.fresh()
			person.travel_book.legacy_pass=true
			if person.region=="jinguashi" or person.region in Mines.IDS or int(person.get("stories",{}).get("bobo",0))>0:
				person.travel_book.visited.jinguashi=true
		if not Transit.valid(person.get("travel_book")):return false
		if person.region in Transit.LOCAL and (not person.travel_book.visited.has(person.region) or Transit.blocked(Vector2i(int(person.x),int(person.y)),person.region)):return false
		if version < 6:person.mine_energy=100
		if not whole(person.get("mine_energy"),100):return false
		if person.has("ginger_warm_until") and not number(person.ginger_warm_until,0,float(s.time)+480.0):return false
		if not MealBuff.valid(person,float(s.time)):return false
		if person.has("blue_outfit") and not person.blue_outfit is bool:return false
		if person.has("blue_outfit_unlocked") and not person.blue_outfit_unlocked is bool:return false
		if person.region in Mines.IDS and Mines.IDS.find(person.region)>=int(s.mine_depths.get("unlocked",0)):return false
		if version < 5 and person.region == Regions.JINGUASHI:return false
		if person.region != Regions.HOME and not Regions.land(Vector2i(int(person.x),int(person.y)),person.region):return false
	for region in Regions.ALL:
		if region == Regions.HOME:continue
		var local = s.regions.get(region)
		if not local is Dictionary or local.size() != Regions.LAYERS.size():return false
		var projection := s.duplicate(false)
		for field in Regions.LAYERS:
			if not local.has(field):return false
			projection[field] = local[field]
		projection.community = {"table":""}
		if not validate_region(projection,crops,build,recipes,size,tree_time):return false
		if projection.objects.values().any(func(obj):return obj.type==Industry.COAST_CART):return false
		for field in ["crops","objects","ground","roofs","forest","removed","damage"]:
			for key in local[field]:
				var parts: PackedStringArray = key.split(",")
				var tile := Vector2i(int(parts[0]),int(parts[1]))
				if not Regions.land(tile,region):return false
				if field not in ["removed","damage"] and (Regions.water(tile,region) or Regions.protected(tile,region)):return false
				if region==Regions.Springs.REGION and field not in ["removed","damage"]:
					if field!="objects" or local[field][key].get("type")!=resident_goals.STONE_BENCH:return false
	# Version 27 edge layers: home is the top level, every region its own layer; all
	# share the global player table (owners are persistent players) and map size.
	if not edge_layer_valid(s.get("edges"),s.players,size):return false
	for region in Regions.ALL:
		if region!=Regions.HOME and not edge_layer_valid(s.regions[region].get("edges"),s.players,size):return false
	if not discovery_groups_valid(s,{"fish":Collections.FISH,"crops":crops,"meals":recipes,"shore":Collections.SHORE_FINDS},true):return false
	if not auto_roofs_valid(s,version):return false
	if version < 3 and not s.has("lanyang_life"):s.lanyang_life=LanyangLife.fresh()
	if not LanyangLife.valid(s):return false
	if version < 4 and not s.has("history_memory"):s.history_memory=HistoryMemory.fresh()
	if not HistoryMemory.valid(s) or not Jinguashi.valid(s):return false
	if version < 7 and not s.has("mine_freight"):s.mine_freight=Freight.fresh()
	if not Freight.valid(s):return false
	if not Bobo.valid(s):return false
	if version<10 and not s.has("station_life"):s.station_life=StationLife.fresh()
	if not StationLife.valid(s):return false
	var waterworks_owners:Dictionary={}
	for layer in [s.objects]+s.regions.values().map(func(region):return region.objects):
		for device in layer.values():
			if device.type!="waterworks":continue
			if version<11 or int(s.mine_depths.unlocked)<4 or not s.players.has(device.owner):return false
			waterworks_owners[device.owner]=int(waterworks_owners.get(device.owner,0))+1
			if waterworks_owners[device.owner]>Waterworks.LIMIT:return false
	# T067: the glass furnace plan only exists after the Q07 hoist repair.
	if not Mines.hoist_ready(s.mine_depths):
		for layer in [s.objects]+s.regions.values().map(func(region):return region.objects):
			if layer.values().any(func(device):return device.type=="glass_furnace"):return false
	var drills:Dictionary={}
	if s.objects.values().any(func(device):return device.type=="mine_drill"):return false
	for region in s.regions:
		var count:=0
		for key in s.regions[region].objects:
			var device:Dictionary=s.regions[region].objects[key]
			if device.type!="mine_drill":continue
			count+=1
			if version<12 or count>1 or region not in MineDrill.REGIONS or int(s.mine_depths.unlocked)<5 or not s.players.has(device.owner):return false
			var parts:PackedStringArray=key.split(",")
			var direction:=MineDrill.placement(Vector2i(int(parts[0]),int(parts[1])))
			if direction<0 or int(device.dir)!=direction:return false
			drills[device.owner]=int(drills.get(device.owner,0))+1
			if drills[device.owner]>MineDrill.LIMIT:return false
			var product:=MineDrill.output(region)
			if not device.items.is_empty() and (device.items.size()!=1 or not whole(device.items.get(product.item),MineDrill.OUTPUT_CAP) or device.items[product.item]<1):return false
			if device.has("job"):
				if int(device.items.get(product.item,0))+int(product.quantity)>MineDrill.OUTPUT_CAP:return false
				if float(s.mine_depths.ready.get(region,{}).get(MineDrill.NODE_KEY,0))>float(device.job.ready)-MineDrill.DURATION:return false
	if version<13 and not s.has("mine_auto_freight"):s.mine_auto_freight=AutoFreight.fresh()
	if not AutoFreight.valid(s):return false
	if version<14:s.mine_survey=Survey.fresh()
	if not Survey.valid(s):return false
	if version<15:s.tea_ceramics=TeaCeramics.fresh()
	if version==15 and not TeaCeramics.migrate_15(s):return false
	if not TeaCeramics.valid(s):return false
	# Version 25 flower nursery. legacy_clean judges the candidate as written, so
	# the fresh tianwei region added above is detached for the check only.
	if int(version)<FLOWER_VERSION:
		if s.has("flower_nursery"):return false
		var added_region=s.regions[FlowerNursery.REGION]
		s.regions.erase(FlowerNursery.REGION)
		var clean:bool=FlowerNursery.legacy_clean(s) and flower_legacy_extra_clean(s)
		s.regions[FlowerNursery.REGION]=added_region
		if not clean:return false
		s.flower_nursery=FlowerNursery.fresh()
	if not FlowerNursery.valid(s):return false
	# Version 26 salt pans. legacy_clean judges the candidate as written, so the
	# fresh beimen region added above is detached for the check only.
	if int(version)<SALT_VERSION:
		if s.has("salt_pan"):return false
		var added_beimen=s.regions[SaltPan.REGION]
		s.regions.erase(SaltPan.REGION)
		var salt_clean:bool=SaltPan.legacy_clean(s) and salt_legacy_extra_clean(s)
		s.regions[SaltPan.REGION]=added_beimen
		if not salt_clean:return false
		s.salt_pan=SaltPan.fresh()
	if not SaltPan.valid(s):return false
	# Version 18 (T034): server-only construction undo history. Older saves never
	# carried undo data; nothing is reverse-inferred from existing buildings.
	if version<18:s.construction=ConstructionHistory.fresh()
	if not construction_valid(s,crops,build,recipes,size,tree_time):return false
	# Version 19: v18 history is kept exactly as-is (no rewrite); a pre-19 save
	# can never have recorded a blueprint transaction.
	if version<BLUEPRINT_HISTORY_VERSION:
		for token in s.construction.last:
			if s.construction.last[token].action=="blueprint":return false
	if version<EDGE_VERSION:
		for entry:Dictionary in s.construction.last.values():
			if entry.action in ["build_edge","remove_edge","edge_blueprint"] or entry.record.get("changes",{}).has("edges"):return false
	# Version 20: stove cooking queues were already validated per layer by
	# validate_region (which read the ORIGINAL input version). Record ids must
	# also be unique across every stove in the world. Legacy `stove.job` is kept
	# untouched; World converts it lazily on the first queue request, never here.
	# Version 21: processing queues were validated per layer the same way; ids
	# must be unique across every cooking AND processing queue in every region.
	# Legacy sawmill/kiln `job` (manual or auto) is kept untouched as well.
	if not queue_ids_unique(s):return false
	# Version 22: box_id shape/type/version were checked per layer by
	# validate_region (input version); ids must also be unique across every live
	# object layer. Chests without box_id are never given one here.
	if not box_ids_unique(s):return false
	# Version 23 public kitchen. Checked HERE, once, against the top-level (home)
	# layers after validate_region already normalised home objects/picnic/
	# community. Never inside validate_region: region projections and
	# construction-history before/after projections shallow-copy this root field
	# and must not validate the home site against another layer's objects.
	if int(version)<PUBLIC_KITCHEN_VERSION:
		if s.has("public_kitchen"):return false
		s.public_kitchen=public_kitchen_fresh()
	if not public_kitchen_valid(s,size):return false
	if not preload("res://scripts/mill_restoration.gd").valid(s):return false
	# T067 共餐桌保溫底座（不升版）：state.table_warmer 可省略；存在時只能是
	# {"installed":true}，且需已野餐、共餐桌有位置；保溫一輪（hotpot 有 total）需已加裝。
	# Top level only, like the public kitchen: region projections replace community.
	if not preload("res://scripts/table_warmer.gd").valid(s):return false
	# 第 40 章蘭陽回訪（不升版）：state.lanyang_revisit 可省略；存在時由 LanyangRevisit.valid
	# 檢查形狀、前提（水圳修好＋配水紀念牌）、當天放晴且閘門符合季節需求、領取者已完成
	# 自己的第一次分水。分流閘與擺出的分水木牌只能出現在回訪完成之後。
	var revisit:=preload("res://scripts/lanyang_revisit.gd")
	if not revisit.valid(s):return false
	# 水塔（第 40 章，同一個解鎖）：擺出的水塔，以及背包／箱子裡的 water_tower_kit 也只能在回訪完成後出現。
	if not revisit.artifacts_valid(s,[Industry.GATE_KIND,revisit.PLAQUE_KIND,Industry.TOWER_KIND],[Industry.TOWER_KIT]):return false
	# 第 40 章金瓜石回訪（不升版）：state.jinguashi_revisit 可省略；存在時由 JinguashiRevisit.valid
	# 檢查形狀、前提（升降台已修好）、送出後分揀符合訂單季節、完成與完成日一致、領取者已跟波波
	# 整理過礦樣。擺出的礦燈與背包／箱子裡的礦燈只能出現在回訪完成之後。
	var jg_revisit:=preload("res://scripts/jinguashi_revisit.gd")
	if not jg_revisit.valid(s):return false
	if not jg_revisit.artifacts_valid(s):return false
	# 第 40 章金瓜石河邊淘砂金（不升版）：state.gold_panning 可省略；存在時恰為 {"players":{token:
	# {stage,day,count,total}}}，token 都是世界裡的玩家，盤數與日期一致。
	if not preload("res://scripts/gold_panning.gd").valid(s):return false
	# 第 40 章金瓜石運礦路線（不升版）：state.ore_route 可省略；形狀與淘砂金相同（stage 0..7、每日 2 車）。
	if not preload("res://scripts/ore_route.gd").valid(s):return false
	# 第 40 章貓空與鶯歌回訪（不升版）：state.tea_revisit 可省略；存在時由 TeaRevisit.valid 檢查
	# 形狀、空罐與裝罐數量、裝茶後各焙法不超過訂單季節、完成與完成日一致、領取者已跟茶茶完成
	# 兩種包裝比較（TeaCeramics.valid 已在前面檢查過）。擺出的茶陶組與背包／箱子裡的茶陶組只能
	# 出現在回訪完成之後。
	var tea_revisit:=preload("res://scripts/tea_revisit.gd")
	if not tea_revisit.valid(s):return false
	if not tea_revisit.artifacts_valid(s):return false
	if not tea_revisit.house_valid(s):return false
	if s.has(tea_revisit.HOUSE_KEY) and not preload("res://scripts/tea_service.gd").valid_round(s,s[tea_revisit.HOUSE_KEY]):return false
	# 第 40 章茶陶上桌（不升版）：state.tea_service 可省略；存在時需已野餐、共餐桌有位置、
	# 茶罐大單已完成、出借人與喝過的人都是世界裡的玩家，杯數＝6−喝過的人數。
	if not preload("res://scripts/tea_service.gd").valid(s):return false
	# 第 40 章臺南北門回訪（不升版）：state.salt_revisit 可省略；存在時由 SaltRevisit.valid 檢查
	# 形狀、入倉與裝籃數量、雨天裝籃數、裝籃後各用途不超過訂單季節、完成與完成日一致、北門閘門
	# 已修好、領取者在北門親手收過鹽（SaltPan.valid 已在前面檢查過）。擺出的鹽籃與背包／箱子裡的
	# 鹽籃只能出現在回訪完成之後。
	var salt_revisit:=preload("res://scripts/salt_revisit.gd")
	if not salt_revisit.valid(s):return false
	if not salt_revisit.artifacts_valid(s):return false
	# 第 40 章北門儲滷槽（不升版）：state.salt_brine 可省略；存在時恰為 {"level":0..30 的整數}，
	# 北門閘門已修好且至少一位已知玩家親手收過鹽。
	if not preload("res://scripts/salt_brine.gd").valid(s):return false
	# 第 40 章風鈴節廣場地方記憶展（不升版）：player.memory_exhibit 可省略；存在時由
	# MemoryExhibit.valid 檢查形狀、已知且不重複的展品、風鈴節已開幕、看過的展品已展出。
	if not preload("res://scripts/memory_exhibit.gd").valid(s):return false
	# T015 交易稽核日誌（不升版）：state.ledger 可省略（舊存檔沒有，第一筆經濟交易提交時才建立）；
	# 存在時由 TransactionLedger.valid 檢查形狀、容量、序號遞增、假名／請求摘要格式，並把 JSON 浮點數還原成整數。
	if not preload("res://scripts/transaction_ledger.gd").valid(s,Regions.ALL):return false
	# Stamp only after every region projection/history check used the input version.
	s.version = VERSION
	return true

## One sparse edge layer. Exact, no repair: Dictionary; every key a canonical
## EdgeGrid key inside `size` (decode rejects non-String, S/E letters, signs, leading
## zeros, whitespace, off-map); every row a Dictionary with exactly type + owner
## (+ open only for edge_door, which requires it as a bool); owner is a non-empty
## token of at most 64 characters (owner()) that exists in `players`. Size can never
## exceed the number of real edges 2*area+width+height (distinct canonical keys),
## which is also checked so a malformed layer cannot be oversized. No per-player cap.
static func edge_layer_valid(layer:Variant,players:Variant,size:Vector2i) -> bool:
	if not layer is Dictionary or not players is Dictionary:return false
	if layer.size()>2*size.x*size.y+size.x+size.y:return false
	for key in layer:
		if EdgeGrid.decode(key,size).is_empty():return false
		var row:Variant=layer[key]
		if not row is Dictionary:return false
		var kind:Variant=row.get("type")
		if not kind is String or kind not in EDGE_TYPES:return false
		var token:Variant=row.get("owner")
		if not owner(token) or not players.has(token):return false
		if kind=="edge_door":
			if row.size()!=3 or not row.get("open") is bool:return false
		elif row.size()!=2 or row.has("open"):return false
	return true

## Unregistered public kitchen: no stove, no seats, nothing contributed, closed.
static func public_kitchen_fresh() -> Dictionary:
	var meals:Dictionary={}
	for meal in KITCHEN_MEALS:meals[meal]=0
	return {"stove":"","seats":[],"meals":meals,"opened":false}

## Version 23 public kitchen invariants (exact, no repair):
## - exact keys stove:String, seats:Array, meals:Dictionary, opened:bool;
## - meals has exactly soup/bread/salad, each a whole number 0..requirement
##   (4/2/2; JSON floats normalised to int); opened == every meal at its cap;
## - unregistered (stove==""): seats==[], all meals 0, opened false;
## - registered: picnic true and a valid shared Community table; stove and two
##   seats are canonical in-bounds "x,y" HOME cells, all distinct, seats sorted
##   strictly ascending by String comparison, none on the table cell; live
##   s.objects hold a "stove" at stove and "long_bench" at both seats, all three
##   with the same owner, who is an existing persistent player; stove within
##   Euclidean 8 tiles of the table, each seat within 3 of the stove (inclusive).
## Deliberately NOT save invariants: stove idleness (it must keep cooking after
## donation) and cardinal path access (later unrelated building may block a
## path; World checks access at registration time and keeps donated cells
## protected). Reads only `s.objects` (home) — call with the home-oriented root.
static func public_kitchen_valid(s:Dictionary,size:Vector2i) -> bool:
	var data = s.get("public_kitchen")
	if not data is Dictionary or data.size()!=KITCHEN_KEYS.size():return false
	for field in KITCHEN_KEYS:
		if not data.has(field):return false
	if not data.stove is String or not data.seats is Array or not data.meals is Dictionary or not data.opened is bool:return false
	if data.meals.size()!=KITCHEN_MEALS.size():return false
	var full:=true
	var empty:=true
	for meal in KITCHEN_MEALS:
		if not data.meals.has(meal) or not whole(data.meals[meal],KITCHEN_MEALS[meal]):return false
		data.meals[meal]=int(data.meals[meal])
		if data.meals[meal]!=int(KITCHEN_MEALS[meal]):full=false
		if data.meals[meal]!=0:empty=false
	if data.opened!=full:return false
	if data.stove.is_empty():
		return data.seats.is_empty() and empty
	if s.get("picnic")!=true:return false
	var table:Vector2i=Community.table_cell(s)
	if table==Community.NO_CELL:return false
	if not location(data.stove,size) or data.seats.size()!=KITCHEN_SEAT_COUNT:return false
	for seat in data.seats:
		if not seat is String or not location(seat,size):return false
	if not (data.seats[0]<data.seats[1]):return false
	var stove_cell:=_kitchen_cell(data.stove)
	var cells:Array=[data.stove]+data.seats
	for key in cells:
		if key==Community.cell_key(table):return false
	if data.stove in data.seats:return false
	var objects = s.get("objects")
	var players = s.get("players")
	if not objects is Dictionary or not players is Dictionary:return false
	var stove = objects.get(data.stove)
	# C12: the donated stove is the early 1x1 小石灶 or the 2x2 公共廚房灶台 (anchor cell only; the other
	# three cells are validated with the rest of the footprint by the construction rules).
	if not stove is Dictionary or stove.get("type") not in [KITCHEN_STOVE_TYPE,Industry.KITCHEN_STOVE]:return false
	if stove.get("type")==Industry.KITCHEN_STOVE and int(stove.get(Industry.KITCHEN_STOVE_PART,0))!=0:return false
	var donor = stove.get("owner")
	if not owner(donor) or not players.has(donor):return false
	if (stove_cell-table).length_squared()>KITCHEN_STOVE_RANGE*KITCHEN_STOVE_RANGE:return false
	for seat in data.seats:
		var bench = objects.get(seat)
		if not bench is Dictionary or bench.get("type")!=KITCHEN_SEAT_TYPE or bench.get("owner")!=donor:return false
		if (_kitchen_cell(seat)-stove_cell).length_squared()>KITCHEN_SEAT_RANGE*KITCHEN_SEAT_RANGE:return false
	return true

## Call only on a key that already passed location().
static func _kitchen_cell(key:String) -> Vector2i:
	var parts:PackedStringArray=key.split(",")
	return Vector2i(int(parts[0]),int(parts[1]))

## Shared, identity-free projection for snapshots: only the four contract keys,
## deep-copied; any malformed live value publishes as fresh instead.
static func public_kitchen_public(state:Dictionary) -> Dictionary:
	var data = state.get("public_kitchen")
	if not data is Dictionary or not data.get("stove") is String or not data.get("seats") is Array or not data.get("meals") is Dictionary or not data.get("opened") is bool:
		return public_kitchen_fresh()
	var meals:Dictionary={}
	for meal in KITCHEN_MEALS:
		var value = data.meals.get(meal,0)
		meals[meal]=int(value) if (value is int or value is float) else 0
	var seats:Array=[]
	for seat in data.seats:
		if seat is String:seats.append(seat)
	return {"stove":String(data.stove),"seats":seats,"meals":meals,"opened":bool(data.opened)}

# Version 20 stove cooking queue. `cooking` is optional, only on stoves, never
# alongside the legacy single `job`, and only in saves written at version >=20
# (an older save carrying it is unknown forward state). The shape, bounds,
# owners (<=64), ids, recipe kinds/version, durations and world-time ordering
# are checked by CookingQueue.validate; malformed state rejects the whole save
# and is never replaced with an empty queue. Stored ingredients/yield/duration
# are historical snapshots and may differ from today's recipes.
static func cooking_valid(s:Dictionary,obj:Dictionary,recipes:Dictionary) -> bool:
	var version = s.get("version",0)
	if not whole(version,VERSION) or int(version)<COOKING_QUEUE_VERSION:return false
	if not Industry.is_stove(str(obj.get("type",""))) or obj.has("job"):return false
	var cooking = obj.cooking
	if not cooking is Dictionary:return false
	if not CookingQueue.validate(cooking,recipes,float(s.time)):return false
	if not bakery_ok(s) and _queue_has_kind(cooking,BAKERY_RECIPES):return false
	normalize_queue(cooking)
	return true

# Version 21 sawmill/charcoal_kiln processing queue (version 24 adds the mill,
# itself only valid from 24 on). `processing` is optional,
# only on those stations, only in saves written at version >=21 (an older
# save carrying it is rejected, never erased), never alongside an authoritative
# legacy `job` (manual or auto) and never while auto_enabled is true. Every
# record owner must equal the station owner. Shape, bounds, ids, kinds and
# world-time ordering follow exactly the CookingQueue semantics against
# Industry.PROCESS filtered to this station; stored ingredients/yield/duration
# are historical snapshots and may differ from today's recipe. input_wood and
# items (the automatic buffer) are validated by the processor rules and kept.
static func processing_valid(s:Dictionary,obj:Dictionary) -> bool:
	var version = s.get("version",0)
	if not whole(version,VERSION) or int(version)<PROCESSING_QUEUE_VERSION:return false
	if obj.get("type") not in PROCESSING_STATIONS or obj.has("job"):return false
	var auto = obj.get("auto_enabled",false)
	if not auto is bool or auto:return false
	var processing = obj.processing
	if not processing is Dictionary:return false
	if not CookingQueue.validate(processing,processing_recipes(obj.type),float(s.time)):return false
	for record in cooking_records(processing):
		if record.owner!=obj.owner:return false
	normalize_queue(processing)
	return true

## Version 24: true when the candidate (or a projection copying its input
## version) was written at a version that knows the bakery ids.
static func bakery_ok(s:Dictionary) -> bool:
	var version = s.get("version",0)
	return whole(version,VERSION) and int(version)>=BAKERY_VERSION

## Version 25 forward-state locations that FlowerNursery.legacy_clean does not
## own: chapter-one harvest tallies and construction-history regions/snapshot
## item counts. Read-only and defensive (runs before construction_valid).
static func flower_legacy_extra_clean(s:Dictionary) -> bool:
	var forward:Array=FlowerNursery.FORWARD_IDS
	var chapter = s.get("chapter_one")
	if chapter is Dictionary and chapter.get("harvests") is Dictionary:
		for owner_token in chapter.harvests:
			var entries = chapter.harvests[owner_token]
			if not entries is Dictionary:continue
			for item in entries:
				if item in forward:return false
	var history = s.get("construction")
	if history is Dictionary and history.get("last") is Dictionary:
		for owner_token in history.last:
			var entry = history.last[owner_token]
			if not entry is Dictionary:continue
			if entry.get("region") in forward:return false
			var changes = entry.get("record",{}).get("changes",{}) if entry.get("record") is Dictionary else {}
			if not changes is Dictionary:continue
			for layer in changes.values():
				if not layer is Dictionary:continue
				for change in layer.values():
					if not change is Dictionary:continue
					for side in ["before","after"]:
						var obj = change.get(side)
						if obj is Dictionary and obj.get("items") is Dictionary:
							for item in obj.items:
								if item in forward:return false
	return true

## Version 26 forward-state locations that SaltPan.legacy_clean may not own:
## chapter-one harvest tallies and construction-history regions/snapshot item
## counts (same scan as the flower check, against SaltPan.FORWARD_IDS).
static func salt_legacy_extra_clean(s:Dictionary) -> bool:
	var forward:Array=SaltPan.FORWARD_IDS
	var players = s.get("players")
	if players is Dictionary:
		for person in players.values():
			if not person is Dictionary:continue
			if person.get("region") in forward:return false
			var book = person.get("travel_book")
			if book is Dictionary and book.get("visited") is Dictionary:
				for place in book.visited:
					if place in forward:return false
			var collection = person.get("collection")
			if collection is Dictionary:
				for group in collection.values():
					if not group is Dictionary:continue
					for id in group:
						if id in forward:return false
	return forward_extra_clean(s,forward)

static func forward_extra_clean(s:Dictionary,forward:Array) -> bool:
	var chapter = s.get("chapter_one")
	if chapter is Dictionary and chapter.get("harvests") is Dictionary:
		for owner_token in chapter.harvests:
			var entries = chapter.harvests[owner_token]
			if not entries is Dictionary:continue
			for item in entries:
				if item in forward:return false
	var history = s.get("construction")
	if history is Dictionary and history.get("last") is Dictionary:
		for owner_token in history.last:
			var entry = history.last[owner_token]
			if not entry is Dictionary:continue
			if entry.get("region") in forward:return false
			var changes = entry.get("record",{}).get("changes",{}) if entry.get("record") is Dictionary else {}
			if not changes is Dictionary:continue
			for layer in changes.values():
				if not layer is Dictionary:continue
				for change in layer.values():
					if not change is Dictionary:continue
					for side in ["before","after"]:
						var obj = change.get(side)
						if obj is Dictionary and obj.get("items") is Dictionary:
							for item in obj.items:
								if item in forward:return false
	return true

## Any queue record whose kind is a bakery-only id (pre-24 forward state).
static func _queue_has_kind(queue,kinds:Array) -> bool:
	if not queue is Dictionary:return false
	for record in cooking_records(queue):
		if str(record.get("kind","")) in kinds:return true
	return false

## Industry.PROCESS entries whose station matches, in the CookingQueue recipe
## shape (extra "station" key dropped). A sawmill can never hold charcoal etc.
static func processing_recipes(station:String) -> Dictionary:
	if station=="seed_maker":
		return SeedMaker.queue_recipes()
	var catalog:Dictionary={}
	for kind in Industry.PROCESS:
		var recipe:Dictionary=Industry.PROCESS[kind]
		if not Industry.uses_station(kind,station):continue
		catalog[kind]={"ingredients":recipe.ingredients.duplicate(true),"time":recipe.time,"yield":recipe.yield}
	return catalog

## Exactly BOX_ID_LENGTH characters of 0-9a-f (no uppercase, no prefix).
static func valid_box_id(value) -> bool:
	if not value is String or value.length()!=BOX_ID_LENGTH:return false
	for c in value:
		if not "0123456789abcdef".contains(c):return false
	return true

# Version 22 material-source identity. `box_id` is optional and lazy: only on
# chest/private_chest, only in saves written at version >=22 (an older save
# carrying it is unknown forward state and rejected, never stripped), exact
# 32 lowercase hex. Absence is always valid; nothing is added on load.
static func box_id_valid(s:Dictionary,obj:Dictionary) -> bool:
	var version = s.get("version",0)
	if not whole(version,VERSION) or int(version)<MATERIAL_SOURCE_VERSION:return false
	if obj.get("type") not in BOX_TYPES:return false
	return valid_box_id(obj.box_id)

## Version 22: one box_id space across the home object layer and every region's
## object layer (live state only; history before/after snapshots are not live).
static func box_ids_unique(s:Dictionary) -> bool:
	var seen:Dictionary={}
	for layer in [s.objects]+s.regions.values().map(func(region):return region.objects):
		for device in layer.values():
			if not device.has("box_id"):continue
			if seen.has(device.box_id):return false
			seen[device.box_id]=true
	return true

## Call only after CookingQueue.validate accepted the queue. JSON loads whole
## numbers as floats; normalise counts like counts() does.
static func normalize_queue(queue:Dictionary) -> void:
	for record in cooking_records(queue):
		record["yield"]=int(record["yield"])
		record.recipe_version=int(record.recipe_version)
		for item in record.ingredients:record.ingredients[item]=int(record.ingredients[item])
		for field in ["duration","started","finish","completed"]:
			if record.has(field):record[field]=float(record[field])

static func cooking_records(cooking:Dictionary) -> Array:
	var records:Array=[]
	if not cooking.active.is_empty():records.append(cooking.active)
	records.append_array(cooking.waiting)
	records.append_array(cooking.ready)
	return records

## Kept for existing callers: uniqueness across stove cooking queues only.
static func cooking_ids_unique(s:Dictionary) -> bool:
	return _ids_unique(s,["cooking"])

## Version 21: one id space shared by every cooking and processing queue in
## the home layer and every region.
static func queue_ids_unique(s:Dictionary) -> bool:
	return _ids_unique(s,["cooking","processing"])

static func _ids_unique(s:Dictionary,fields:Array) -> bool:
	var seen:Dictionary={}
	for layer in [s.objects]+s.regions.values().map(func(region):return region.objects):
		for device in layer.values():
			for field in fields:
				if not device.has(field):continue
				for record in cooking_records(device[field]):
					if seen.has(record.id):return false
					seen[record.id]=true
	return true

# Version 18 construction history. Shape/ownership/ids/timestamps/watches are
# strict (ConstructionHistory.validate); every recorded before/after entry of a
# LIVE record is then re-validated with the normal region rules so a corrupt
# historical machine cannot be restored by undo past the regular save checks.
static func construction_valid(s:Dictionary,crops:Dictionary,build:Dictionary,recipes:Dictionary,size:Vector2i,tree_time:float) -> bool:
	if not ConstructionHistory.validate(s,size,build,Regions.ALL):return false
	for token in s.construction.last:
		var entry:Dictionary=s.construction.last[token]
		if entry.status!="live":continue
		var region:String=entry.region
		var changes:Dictionary=entry.record.changes
		for side in ["before","after"]:
			var projection:=s.duplicate(false)
			for field in ["crops","objects","ground","roofs","forest","removed","damage"]:projection[field]={}
			for layer in ["ground","objects","roofs"]:
				for key in changes[layer]:
					var entry_value=changes[layer][key][side]
					if entry_value!=null:projection[layer][key]=entry_value.duplicate(true)
			if not validate_region(projection,crops,build,recipes,size,tree_time,true):return false
			for layer in ["ground","objects","roofs"]:
				for key in projection[layer]:
					var parts:PackedStringArray=key.split(",")
					var tile:=Vector2i(int(parts[0]),int(parts[1]))
					if region!=Regions.HOME and (not Regions.land(tile,region) or Regions.water(tile,region) or Regions.protected(tile,region)):return false
					var obj:Dictionary=projection[layer][key]
					if obj.has("auto") and (layer!="roofs" or not obj.auto is bool):return false
					if obj.type=="mine_drill":
						if region not in MineDrill.REGIONS or MineDrill.placement(tile)<0 or int(obj.dir)!=MineDrill.placement(tile):return false
						if obj.has("job") and not obj.job is Dictionary:return false
	return true

# Version 17 auto-roof marker. Runs after every layer passed validate_region so
# objects are well-formed, and uses the global player table plus the candidate's
# original version (region projections know neither).
# - "auto" may appear only on roofs; any "auto" key on ground/objects is rejected.
# - auto must be bool. auto=true requires version>=17, a floor under the same
#   tile in the same layer, and an owner that is a persistent player (payer may
#   differ from the floor owner). Pre-17 auto=true is rejected, never adopted.
# - auto=false (any version) is a manual roof and is preserved as-is.
# - Roofs without the key keep the old manual semantics: no floor/owner tightening,
#   and nothing is added or converted on load.
static func auto_roofs_valid(s:Dictionary,version) -> bool:
	var layers:Array=[s]
	for region in s.regions:layers.append(s.regions[region])
	for layer in layers:
		for field in ["objects","ground"]:
			for obj in layer[field].values():
				if obj.has("auto"):return false
		for key in layer.roofs:
			var roof:Dictionary=layer.roofs[key]
			if not roof.has("auto"):continue
			if not roof.auto is bool:return false
			if not roof.auto:continue
			if roof.type!="roof":return false
			if version<17:return false
			var below = layer.ground.get(key)
			if not RoomEnclosure.is_floor_piece(below):return false
			if not s.players.has(roof.owner):return false
	return true

static func discovery_groups_valid(source:Dictionary,catalogs:Dictionary,island:bool) -> bool:
	for category in ["fish","crops","meals","shore"]:
		var field:String=("island_" if island else "")+str(category)+"_discoveries"
		var entries=source.get(field,{})
		if not entries is Dictionary or entries.size()>catalogs[category].size():return false
		for id in entries:
			var entry=entries[id]
			if not catalogs[category].has(id) or not entry is Dictionary or entry.size()!=(3 if island else 2):return false
			if category=="meals" and not Collections.is_meal(id):return false
			if island and (not entry.get("name") is String or entry.name.length()>12):return false
			if entry.get("region") not in Regions.ALL:return false
			if not whole(entry.get("day"),9000000000000001.0) or int(entry.day)<1:return false
			entry.day=int(entry.day)
	return true

static func validate_region(s:Dictionary,crops:Dictionary,build:Dictionary,recipes:Dictionary,size:Vector2i,tree_time:float,partial_history:=false) -> bool:
	if not number(s.get("time")) or not whole(s.get("committed")) or not s.get("board") is bool:return false
	if not s.has("next_network_check"):s.next_network_check=0.0
	# JSON rounds the stored clock and deadlines independently.
	const CLOCK_ROUNDING:=0.000001
	if not number(s.next_network_check,0,float(s.time)+Industry.INTERVAL+CLOCK_ROUNDING):return false
	if not s.has("next_logistics_check"):s.next_logistics_check=0.0
	if not number(s.next_logistics_check,0,float(s.time)+Logistics.INTERVAL+CLOCK_ROUNDING):return false
	for field in ["players","crops","objects","ground","removed","damage","donations"]:
		if not s.get(field) is Dictionary:return false
	for field in ["roofs","forest"]:
		if not s.has(field):s[field]={}
		if not s[field] is Dictionary:return false
	if not s.has("chapter_one"):s.chapter_one=ChapterOne.fresh()
	if not ChapterOne.valid(s.chapter_one,s.players,crops,s.board):return false
	if not s.get("events") is Array:return false
	for event in s.events:
		if not event is String:return false
	if not whole(s.donations.get("wood"),30) or not whole(s.donations.get("stone"),10):return false
	if not StoneWorkshop.valid(s):return false
	for token in s.players:
		var personal = s.players[token]
		if personal is Dictionary and personal.has(MUSHROOM_MAIL.RECORD) and not MUSHROOM_MAIL.valid(personal[MUSHROOM_MAIL.RECORD]):return false
		if personal is Dictionary and personal.has(Industry.DESK_DRAFT_FIELD):
			var draft:Variant=personal[Industry.DESK_DRAFT_FIELD]
			if not draft is String or draft.is_empty() or ISLAND_NOTES.clean(draft)!=draft:return false
		if personal is Dictionary and personal.has("news_seen") and not whole(personal.news_seen,ISLAND_NOTES.news_project_limit()):return false
		if personal is Dictionary and personal.has("ferry_recap_seen"):
			var marker:Variant=personal.ferry_recap_seen
			if not whole(marker,IslandStoryRecap.DOCK_STAGES|IslandStoryRecap.BIT_OPENED|IslandStoryRecap.BIT_BAMBOO):return false
			var stage:=int(marker)&3
			if stage>IslandStoryRecap.DOCK_STAGES or (int(marker)>3 and stage<IslandStoryRecap.DOCK_STAGES):return false
		if personal is Dictionary and personal.has("resident_participation"):
			var participation = personal.resident_participation
			if not participation is Dictionary or participation.size()>4:return false
			for event in participation:
				if event not in ["bridge","canal","shipment","shared_meal"] or participation[event]!=true:return false
		var p=s.players[token]
		if not owner(token) or not p is Dictionary or not p.get("name") is String:return false
		var wangan_key:=preload("res://scripts/wangan_memory.gd").KEY
		if p.has(wangan_key) and (not p[wangan_key] is bool or not p[wangan_key]):return false
		var weir_key:=preload("res://scripts/wangan_memory.gd").WEIR_KEY
		if p.has(weir_key) and (not whole(p[weir_key],2) or p[weir_key]<1):return false
		var wangan:=preload("res://scripts/wangan_memory.gd")
		if p.has(ChapterOne.PERSONAL_START) and (not p[ChapterOne.PERSONAL_START] is bool or not p[ChapterOne.PERSONAL_START]):return false
		if p.has(wangan.LOG_KEY) and (not p[wangan.LOG_KEY] is bool or not p[wangan.LOG_KEY] or not wangan.log_ready(p) or int(s.get("dock_stage",0))<1):return false
		# T066 好感：可省略；存在時必須是已知居民的三個整數欄位。
		if p.has("bonds") and not ResidentBond.valid(p.bonds,float(s.time)):return false
		# T066「一起做的事」：可省略；存在時需為有行動的階、合法選項，且好感已到那一階。
		if p.has("bond_goals") and not preload("res://scripts/resident_goals.gd").valid(p.bond_goals,p):return false
		# C12 D05 森林菇湯委託：可省略；存在時是 1..3 的階段，且渡口公告板已修好。
		var forest_commission:=preload("res://scripts/forest_mushroom_commission.gd")
		if p.has(forest_commission.KEY) and not forest_commission.valid(p[forest_commission.KEY],s):return false
		# T066 第三批紀念小物：可省略；存在時只能是已完成行動的紀念小物（值為 true）。
		var goals:=preload("res://scripts/resident_goals.gd")
		if p.has(goals.DIANDIAN_SEAT_KEY) and (not p[goals.DIANDIAN_SEAT_KEY] is bool or not p[goals.DIANDIAN_SEAT_KEY] or not goals.done(p,"diandian").has(1) or goals.Bond.stage(p,"diandian")<2):return false
		if p.has(goals.MASTER_BENCH_SEAT):
			var seat=p[goals.MASTER_BENCH_SEAT]
			if not seat is Dictionary or seat.size()!=2 or not seat.get("cell") is String or not whole(seat.get("side"),3):return false
			if not seat.cell.is_valid_filename():return false
			seat.side=int(seat.side)
		if p.has(goals.VOYAGE_START) and (not number(p[goals.VOYAGE_START],0,float(s.time)) or p.get("region","home")!="home" or goals.Bond.stage(p,"achao")<3):return false
		if p.has(goals.VOYAGE_CAPTAIN) and (not p.has(goals.VOYAGE_START) or not owner(p[goals.VOYAGE_CAPTAIN])):return false
		if p.has(goals.VOYAGE_PHOTO) and (not p[goals.VOYAGE_PHOTO] is bool or not p[goals.VOYAGE_PHOTO] or goals.Bond.stage(p,"achao")<4):return false
		if p.has(goals.VOYAGE_DONE) and (not p[goals.VOYAGE_DONE] is bool or not p[goals.VOYAGE_DONE] or goals.Bond.stage(p,"achao")<3):return false
		if p.has(goals.VOYAGE_PAINT) and (not p[goals.VOYAGE_PAINT] is bool or not p[goals.VOYAGE_PAINT] or not goals.done(p,"achao").has(3)):return false
		if p.has(goals.ARU_PHOTO_KEY) and (p[goals.ARU_PHOTO_KEY]!=true or goals.Bond.stage(p,"aru")<4):return false
		if p.has(goals.ARU_REST_KEY) and (not number(p[goals.ARU_REST_KEY],0,float(s.time)) or goals.Bond.stage(p,"aru")<3):return false
		if p.has(goals.SHEEP_SHELTER_KEY) and (not whole(p[goals.SHEEP_SHELTER_KEY],goals.SHEEP_COMFORT_MASK) or goals.Bond.stage(p,"mianmian")<2):return false
		if p.has(goals.TEA_CHAIR_KEY) and (not p[goals.TEA_CHAIR_KEY] is String or not goals.TEA_CHAIRS.has(p[goals.TEA_CHAIR_KEY]) or goals.Bond.stage(p,"chacha")<4):return false
		if p.has(goals.TEA_SETUP_KEY) and (p[goals.TEA_SETUP_KEY] not in goals.TEA_AXES or goals.Bond.stage(p,"chacha")<1):return false
		if p.has(goals.TEA_TOPICS_KEY) and not goals.valid_tea_topics(p[goals.TEA_TOPICS_KEY],p):return false
		if p.has(goals.PAINT_INVITES_KEY) and (not goals.valid_paint_invites(p[goals.PAINT_INVITES_KEY]) or goals.Bond.stage(p,"diandian")<3):return false
		if p.has(goals.GROWTH_KEY):
			var tracked=p[goals.GROWTH_KEY]
			if not tracked is Dictionary or tracked.size()!=3 or tracked.get("region") not in goals.GROWTH_REGIONS or not location(tracked.get("tile"),size) or not crops.has(tracked.get("kind")):return false
			if goals.Bond.stage(p,"xinghe")<1:return false
		if p.has(goals.GROWTH_LOG_KEY):
			var logbook=p[goals.GROWTH_LOG_KEY]
			if not logbook is Dictionary or logbook.is_empty() or logbook.size()>crops.size() or goals.Bond.stage(p,"xinghe")<1:return false
			for crop_id in logbook:
				if not crops.has(crop_id) or not logbook[crop_id] is bool or not logbook[crop_id]:return false
		if p.has(goals.ADDRESS_KEY) and (not whole(p[goals.ADDRESS_KEY],goals.ADDRESS_DELIVERED) or goals.Bond.stage(p,"luoluo")<1):return false
		if not goals.valid_postcard_clues(p):return false
		if not goals.valid_future_note(p):return false
		if p.has(goals.COURIER_CAP_KEY) and (not p[goals.COURIER_CAP_KEY] is bool or not p[goals.COURIER_CAP_KEY] or p.has(goals.WOOL_HAT_KEY) or not goals.done(p,"luoluo").has(4)):return false
		if p.has(goals.INN_CLEAR_KEY) and (p[goals.INN_CLEAR_KEY]!=true or not p[goals.INN_CLEAR_KEY] is bool or goals.Bond.stage(p,"nuannuan")<1):return false
		var springs:=goals.Springs
		if p.has(springs.CRACK_KEY) and (not whole(p[springs.CRACK_KEY],springs.CRACK_MASK) or int(p[springs.CRACK_KEY])==0 or goals.Bond.stage(p,"nuannuan")<2):return false
		if p.has(goals.GUEST_ROOM_KEY) and (not p[goals.GUEST_ROOM_KEY] is bool or not p[goals.GUEST_ROOM_KEY] or goals.Bond.stage(p,"nuannuan")<3):return false
		if p.has(goals.GUEST_CLOTH_KEY) and (not p[goals.GUEST_CLOTH_KEY] is bool or not p[goals.GUEST_CLOTH_KEY] or not goals.done(p,"nuannuan").has(3)):return false
		var bell_key:=preload("res://scripts/resident_goals.gd").BELL_INSPECT_KEY
		if p.has(bell_key) and not whole(p[bell_key],preload("res://scripts/resident_goals.gd").BELL_INSPECT_MASK):return false
		# T066 N03-4 最後一趟空車：可省略；存在時為有限整數 1..7，且波波好感已到第四階（JSON 浮點數正規化為 int）。
		if not preload("res://scripts/bobo_empty_cart.gd").valid_person(p):return false
		var rest_key:=preload("res://scripts/resident_goals.gd").REST_KIT_KEY
		if p.has(rest_key) and not whole(p[rest_key],preload("res://scripts/resident_goals.gd").REST_KIT_MASK):return false
		var page_key:=preload("res://scripts/resident_goals.gd").RECIPE_PAGE_KEY
		if p.has(page_key) and not whole(p[page_key],preload("res://scripts/resident_goals.gd").RECIPE_PAGE_MASK):return false
		var route_key:=preload("res://scripts/resident_goals.gd").ROUTE_KEY
		if p.has(route_key) and not whole(p[route_key],preload("res://scripts/resident_goals.gd").ROUTE_MASK):return false
		var sketch_key:=preload("res://scripts/resident_goals.gd").SKETCH_KEY
		if p.has(sketch_key) and not preload("res://scripts/resident_goals.gd").valid_sketches(p[sketch_key],crops):return false
		var apron_key:=preload("res://scripts/resident_goals.gd").APRON_KEY
		if p.has(apron_key) and (not p[apron_key] is bool or not p[apron_key] or not preload("res://scripts/resident_goals.gd").apron_unlocked(p)):return false
		var supper_module:=preload("res://scripts/milu_supper.gd")
		if p.has(supper_module.KEY) and not supper_module.valid(p[supper_module.KEY],p):return false # N02-4 optional supper record (strict, no migration)
		if p.has("bond_keepsakes") and not preload("res://scripts/resident_goals.gd").valid_keepsakes(p.bond_keepsakes,p):return false
		if p.has("market") and not preload("res://scripts/market_stall.gd").valid(p.market,float(s.time),{}):return false # T071 市集攤位（可省略）
		if p.has("market_decor") and not preload("res://scripts/market_decor.gd").valid_for_player(p.market_decor,preload("res://scripts/resident_goals.gd").done(p,"xiaoli").has(3)):return false
		if not preload("res://scripts/xiaoli_shop.gd").valid_save(p,preload("res://scripts/resident_goals.gd").done(p,"xiaoli").has(4)):return false
		if p.has(SPRING_GARDEN.KEY):
			if not p[SPRING_GARDEN.KEY] is Dictionary or not SPRING_GARDEN.valid(p[SPRING_GARDEN.KEY]):return false
			p[SPRING_GARDEN.KEY].mask=int(p[SPRING_GARDEN.KEY].mask)
		if p.has(SEA_BREEZE_FAIR.KEY):
			var fair:Variant=p[SEA_BREEZE_FAIR.KEY]
			if not fair is Dictionary or not SEA_BREEZE_FAIR.valid(fair):return false
			fair.served=int(fair.served)
			fair.offset=int(fair.offset)
		if p.has("summer_market") and not preload("res://scripts/summer_market.gd").valid(p.summer_market,float(s.time)):return false # C12 D14 夏季市集食譜（可省略）
		if p.has(FLOUR_STALL_KEY):
			var flour_row=p[FLOUR_STALL_KEY]
			var flour_day:=int(preload("res://scripts/weather.gd").day_index(float(s.time)))
			if not flour_row is Dictionary or flour_row.size()!=2 or not whole(flour_row.get("day"),flour_day) or not whole(flour_row.get("bought"),FLOUR_STALL_DAILY):return false
			flour_row.day=int(flour_row.day)
			flour_row.bought=int(flour_row.bought)
		if p.has(SUGAR_STALL_KEY):
			var sugar_row=p[SUGAR_STALL_KEY]
			var sugar_day:=int(preload("res://scripts/weather.gd").day_index(float(s.time)))
			if not sugar_row is Dictionary or sugar_row.size()!=2 or not whole(sugar_row.get("day"),sugar_day) or not whole(sugar_row.get("bought"),SUGAR_STALL_DAILY):return false
			sugar_row.day=int(sugar_row.day)
			sugar_row.bought=int(sugar_row.bought)
		if p.has("greenhouse_reported"):
			if not p.greenhouse_reported is bool:return false
			if p.greenhouse_reported and (p.get("greenhouse_glass_crafted")!=true or not crops.has(p.get("greenhouse_cross_season_crop",""))):return false
		if p.has(preload("res://scripts/resident_goals.gd").CHICKEN_FED_KEY) and not number(p[preload("res://scripts/resident_goals.gd").CHICKEN_FED_KEY],0,float(s.time)):return false
		if p.has(preload("res://scripts/resident_goals.gd").SHEEP_STEP_KEY) and not number(p[preload("res://scripts/resident_goals.gd").SHEEP_STEP_KEY],0,float(s.time)):return false
		var hat_key:=preload("res://scripts/resident_goals.gd").WOOL_HAT_KEY
		if p.has(hat_key) and (not p[hat_key] is bool or not p[hat_key] or not preload("res://scripts/resident_goals.gd").wool_hat_unlocked(p)):return false
		var trade_key:=preload("res://scripts/resident_goals.gd").CROP_TRADE_KEY
		if p.has(trade_key) and (not whole(p[trade_key],preload("res://scripts/resident_goals.gd").SEED_BOUGHT) or int(p[trade_key])<1):return false
		if not preload("res://scripts/transaction_ledger.gd").valid_first_shop_trade(p,int(p.get(trade_key,0)),preload("res://scripts/resident_goals.gd").CROP_SOLD,preload("res://scripts/resident_goals.gd").SEED_BOUGHT,crops):return false
		if p.has("greenhouse_glass_crafted") and not p.greenhouse_glass_crafted is bool:return false
		if p.has("greenhouse_cross_season_crop") and (not p.greenhouse_cross_season_crop is String or not crops.has(p.greenhouse_cross_season_crop)):return false
		if p.name.length()>12 or not number(p.get("x"),0,size.x) or not number(p.get("y"),0,size.y):return false
		if not counts(p.get("inventory")) or not whole(p.get("coins")):return false
		if p.has("crop_care") and not whole(p.crop_care,preload("res://scripts/crop_catalog.gd").CARE_TARGET):return false
		if p.has("squirrel_day") and not whole(p.squirrel_day,int(preload("res://scripts/weather.gd").day_index(float(s.time)))):return false
		if p.has("seal_seen") and not p.seal_seen is bool:return false
		if p.has("windbell_deer_seen") and (not p.windbell_deer_seen is bool
			or (p.windbell_deer_seen and not s.get("festival_story_open",false))):return false
		if p.has("hedgehog_visit_day") or p.has("hedgehog_observed_day"):
			var day:=int(preload("res://scripts/weather.gd").day_index(float(s.time)))
			if not whole(p.get("hedgehog_visit_day"),day+1) or int(p.hedgehog_visit_day)<1:return false
			if p.has("hedgehog_observed_day"):
				if not whole(p.hedgehog_observed_day,mini(day,int(p.hedgehog_visit_day))) or int(p.hedgehog_observed_day)<1:return false
		if p.has("fox_tracks") and (not whole(p.fox_tracks,7) or int(p.fox_tracks) not in [1,3,5,7]):return false
		if p.has("companion_fox") and int(p.get("fox_tracks",0))!=7:return false
		if p.has("fox_hint_until") and not number(p.fox_hint_until,0,float(s.time)+60.0):return false
		var following_count:=0
		var rules=preload("res://scripts/companion_rabbit.gd")
		for field:String in rules.PET_FIELDS:
			if not p.has(field):continue
			var pet:Variant=p[field]
			if not pet is Dictionary or not pet.get("following") is bool:return false
			var has_reaction:bool=field in ["companion_cat","companion_dog"] and pet.has("last_play")
			if pet.size()!=(4 if has_reaction else 3):return false
			if has_reaction and pet.last_play not in ["pet","yarn" if field=="companion_cat" else "toy"]:return false
			if not whole(pet.get("bond"),rules.MAX_BOND) or not number(pet.get("last_pet"),-rules.PET_INTERVAL,float(s.time)):return false
			following_count+=int(pet.following)
		if following_count>1:return false
		for event_name in ["last_till","last_seed","last_harvest"]:
			if not p.has(event_name):continue
			var till=p[event_name]
			if not till is Dictionary or not number(till.get("at"),0,float(s.time)):return false
			if event_name=="last_seed" and (not till.get("kind") is String or not crops.has(till.kind)):return false
			if event_name=="last_seed" and till.kind in BAKERY_CROPS and not bakery_ok(s):return false
			if not whole(till.get("x"),size.x-1) or not whole(till.get("y"),size.y-1):return false
			till.x=int(till.x)
			till.y=int(till.y)
			if not till.get("cells") is Array or till.cells.is_empty() or till.cells.size()>9:return false
			var tilled:Dictionary={}
			for tile in till.cells:
				if not location(tile,size) or tilled.has(tile):return false
				var coordinates:PackedStringArray=tile.split(",")
				if absi(int(coordinates[0])-int(till.x))>1 or absi(int(coordinates[1])-int(till.y))>1:return false
				tilled[tile]=true
		if p.has("beimen_fishing_misses"):
			if not whole(p.beimen_fishing_misses,Collections.RARE_FISH_LIMIT-1):return false
			if not p.has("beimen_flounder_misses"):p.beimen_flounder_misses=p.beimen_fishing_misses
			p.erase("beimen_fishing_misses")
		for water in Collections.RARE_WATERS.values():
			if p.has(water.counter) and not whole(p[water.counter],Collections.RARE_FISH_LIMIT-1):return false
		var explored = p.get("explored_regions",{})
		if not explored is Dictionary or explored.size()>=Regions.ALL.size():return false
		for area in explored:
			if area==Regions.HOME or area not in Regions.ALL or explored[area]!=true:return false
		if p.has("crafting_points") and not whole(p.crafting_points):return false
		if p.has("workshop_upgraded") and typeof(p.workshop_upgraded)!=TYPE_BOOL:return false
		if p.has("gathering_points") and not whole(p.gathering_points):return false
		if p.has("gathering_assists") and not whole(p.gathering_assists,int(p.get("gathering_points",0))):return false
		# D06 星砂步道海鹽包（選填、各玩家自己的）：兩個欄位成對出現，日序不超過現在、份數不超過終身上限。
		var parcel_rules=preload("res://scripts/wangan_coast.gd")
		if p.has(parcel_rules.SALT_PARCEL_DAY_KEY) or p.has(parcel_rules.SALT_PARCEL_TOTAL_KEY):
			var parcel_day_now:=int(preload("res://scripts/weather.gd").day_index(float(s.time)))+1
			if not p.has(parcel_rules.SALT_PARCEL_DAY_KEY) or not p.has(parcel_rules.SALT_PARCEL_TOTAL_KEY):return false
			if not whole(p[parcel_rules.SALT_PARCEL_DAY_KEY],parcel_day_now) or int(p[parcel_rules.SALT_PARCEL_DAY_KEY])<1:return false
			if not whole(p[parcel_rules.SALT_PARCEL_TOTAL_KEY],parcel_rules.SALT_PARCEL_LIFETIME) or int(p[parcel_rules.SALT_PARCEL_TOTAL_KEY])<1:return false
			p[parcel_rules.SALT_PARCEL_DAY_KEY]=int(p[parcel_rules.SALT_PARCEL_DAY_KEY])
			p[parcel_rules.SALT_PARCEL_TOTAL_KEY]=int(p[parcel_rules.SALT_PARCEL_TOTAL_KEY])
		for counter in ["harvests","builds","fish_caught"]:
			if not p.has(counter):p[counter]=0
			if not whole(p[counter]):return false
			p[counter]=int(p[counter])
		if not p.get("receipts") is Dictionary or p.receipts.size()>128:return false
		for id in p.receipts:
			var receipt=p.receipts[id]
			if not id is String or id.length()>80 or not receipt is Dictionary:return false
			if not receipt.get("ok") is bool or not receipt.get("message") is String:return false
		p.coins=int(p.coins)
		if not p.has("crafted_reinforced_pick"):p.crafted_reinforced_pick=int(p.inventory.get("reinforced_pick",0))>0
		if not p.crafted_reinforced_pick is bool:return false
		if p.has("borrowed_mine_pick") and (not p.borrowed_mine_pick is bool or (p.borrowed_mine_pick and not s.get("picnic",false))):return false
		if not preload("res://scripts/public_tiller.gd").valid(p,s):return false
		if p.has("mud_alcove") and (not whole(p.mud_alcove,2) or int(p.mud_alcove)<1 or not s.get("picnic",false)):return false
		if p.has("sleepy_guardian"):
			# 打瞌睡石像 (B4): optional per-player record; old saves simply lack it.
			var guardian_record=p.sleepy_guardian
			if not preload("res://scripts/sleepy_stone_guardian.gd").valid(guardian_record) or not s.get("picnic",false):return false
			p.sleepy_guardian={"round":int(guardian_record.round),"calm":int(guardian_record.calm),"claimed":guardian_record.claimed}
		if p.has("shy_mushroom"):
			# 害羞菇 (B2): optional per-player record; old saves simply lack it.
			var shy_record=p.shy_mushroom
			if not preload("res://scripts/shy_mushroom.gd").valid(shy_record) or not s.get("picnic",false):return false
			p.shy_mushroom={"stage":int(shy_record.stage),"claimed":shy_record.claimed}
		if p.has("stone_crab"):
			# 石殼蟹 (B5): optional per-player record; old saves simply lack it. B5 must be open.
			var crab_record=p.stone_crab
			# mine_depths is validated later (Mines.valid), so read it defensively here.
			var crab_depths=s.get("mine_depths")
			if not crab_depths is Dictionary or not whole(crab_depths.get("unlocked")) or int(crab_depths.unlocked)<5:return false
			if not preload("res://scripts/stone_shelled_crab.gd").valid(crab_record) or not s.get("picnic",false):return false
			p.stone_crab={"stage":int(crab_record.stage),"claimed":crab_record.claimed}
		var porter:=preload("res://scripts/lost_porter_mouse.gd")
		if p.has(porter.FIELD):
			var depths:Variant=s.get("mine_depths")
			if not depths is Dictionary or not whole(depths.get("unlocked")) or int(depths.unlocked)<porter.DEPTH:return false
			if not s.get("picnic",false) or not porter.valid(p[porter.FIELD]):return false
			p[porter.FIELD]=int(p[porter.FIELD])
		var meadow:=preload("res://scripts/meadow_guardian.gd")
		if p.has(meadow.FIELD):
			var depths:Variant=s.get("mine_depths")
			if not depths is Dictionary or not whole(depths.get("unlocked")) or int(depths.unlocked)<meadow.DEPTH:return false
			if not s.get("picnic",false) or not meadow.valid(p[meadow.FIELD]):return false
			p[meadow.FIELD]=int(p[meadow.FIELD])
		if p.has("mud_duel"):
			var duel=p.mud_duel
			if s.get("world_mode")!="adventure" or not s.get("picnic",false) or p.has("mud_alcove") or not duel is Dictionary or duel.size()!=3:return false
			if not number(duel.get("strike_at"),0,float(s.time)+1.5) or not number(duel.get("origin_x"),0,size.x) or not duel.get("dodged") is bool:return false
		if not Collections.validate(p, crops, recipes):return false
		if not Collections.gallery_valid(p,crops,recipes):return false
		if not discovery_groups_valid(p,p.collection,false):return false
		if not bakery_ok(s):
			for crop_id in BAKERY_CROPS:
				if p.collection.crops.has(crop_id):return false
			for meal_id in BAKERY_RECIPES:
				if p.collection.meals.has(meal_id):return false
		const Village=preload("res://scripts/village.gd")
		Village.ensure_player(p)
		if not p.stories is Dictionary or not p.orders is Dictionary:return false
		if p.stories.size()!=Village.QUESTS.size():return false
		for resident in Village.QUESTS:
			if not whole(p.stories.get(resident),Village.QUESTS[resident].size()):return false
			p.stories[resident]=int(p.stories[resident])
		if not number(p.orders.get("day"),-1) or floorf(float(p.orders.day))!=float(p.orders.day):return false
		if not p.orders.get("done") is Array or p.orders.done.size()>Village.ORDERS.size():return false
		var seen:Dictionary={}
		for order in p.orders.done:
			if not order is String or OrderCatalog.find(order).is_empty() or seen.has(order):return false
			seen[order]=true
		if not orders_active_valid(p.orders,float(s.time)):return false
		if not whole(p.trees_planted) or not whole(p.cooked):return false
		if p.has("fishing"):
			var fish=p.fishing
			if not fish is Dictionary or not whole(fish.get("x"),size.x-1) or not whole(fish.get("y"),size.y-1) or not number(fish.get("ready")):return false
			if fish.has("rod") and not fish.rod in preload("res://scripts/fishing_tracking.gd").ROD_TIERS:return false
			if fish.has("band") or fish.has("aligned_at") or fish.has("tracked"):
				if not number(fish.get("band"),0.0,1.0) or not number(fish.get("tracked"),0.0,3.0):return false
				if not number(fish.get("aligned_at"),float(fish.ready)):return false
	for field in ["crops","objects","ground","roofs","forest","removed","damage"]:
		for k in s[field]:
			if not location(k,size):return false
	for c in s.crops.values():
		if not c is Dictionary or not c.get("kind") is String or not c.get("wet") is bool:return false
		if c.kind!="" and not crops.has(c.kind):return false
		if c.kind in BAKERY_CROPS and not bakery_ok(s):return false
		if not number(c.get("growth"),0,float(crops[c.kind].time) if c.kind!="" else 0.0):return false
		if c.has("other_sown") and (not c.other_sown is bool or not c.other_sown or c.kind==""):return false
		if c.has("owner") and not owner(c.owner):return false
		for policy in ["owner_sow","owner_water"]:
			if c.has(policy) and (not c.has("owner") or not c[policy] is bool or not c[policy]):return false
		if c.has("last_care_day") and not whole(c.last_care_day):return false
		if c.has("fertility") and not whole(c.fertility,1):return false
		if c.has("last_harvest_kind") and (not c.last_harvest_kind is String or not crops.has(c.last_harvest_kind)):return false
		if c.has("harvest_access") and (not c.has("owner") or c.harvest_access not in ["owner","island","friend"]):return false
		if c.get("harvest_access","")=="friend":
			var guest=c.get("harvest_friend")
			if not owner(guest) or guest==c.owner or not s.players.has(guest):return false
		elif c.has("harvest_friend"):return false
		if not c.has("remaining"):c.remaining=0 if c.kind=="" else 1
		if not whole(c.remaining,3):return false
		if c.kind!="" and (int(c.remaining)<1 or int(c.remaining)>int(crops[c.kind].get("cycles",1))):return false
	var sprinkler_owners:Dictionary={}
	var industry_owners:Dictionary={}
	var forestry_owners:Dictionary={}
	var conveyor_owners:Dictionary={}
	for field in ["objects","ground","roofs"]:
		for tile:String in s[field]:
			var obj=s[field][tile]
			if not obj is Dictionary or not build.has(obj.get("type")) or not owner(obj.get("owner")) or not counts(obj.get("items")):return false
			if obj.has("cabinet_shared") and (obj.type not in [Industry.ACORN_CABINET,Industry.TEA_SNACK_SHELF] or not obj.cabinet_shared is bool or not obj.cabinet_shared):return false
			if obj.type==Industry.TEA_SNACK_SHELF:
				# T11: both tiers are the only stock; the generic `items` must stay empty so nothing is counted twice.
				if field!="objects" or not obj.items.is_empty():return false
				if not obj.has(Industry.SNACK_FIELD):obj[Industry.SNACK_FIELD]=Industry.fresh_snack_tiers()
				if not Industry.valid_snack_tiers(obj[Industry.SNACK_FIELD],recipes):return false
				for tier:Dictionary in obj[Industry.SNACK_FIELD]:
					for item:String in tier.keys():tier[item]=int(tier[item])
			elif obj.has(Industry.SNACK_FIELD):return false
			if obj.type==Industry.ACORN_CABINET:
				if field!="objects" or obj.items.size()>Industry.CABINET_SLOTS:return false
				for item:String in obj.items:
					if int(obj.items[item])<=0 or not ItemCatalog.is_known(item):return false
			if obj.has("placement_access") and (field!="ground" or not RoomEnclosure.is_floor_kind(obj.type) or obj.placement_access not in ["owner","island"]):return false
			if obj.has("owner_visit") and (field!="ground" or not RoomEnclosure.is_floor_kind(obj.type) or not obj.owner_visit is bool or not obj.owner_visit):return false
			if obj.has("visit_guest"):
				var visitor=obj.visit_guest
				if obj.get("owner_visit")!=true or not owner(visitor) or visitor==obj.owner or not s.players.has(visitor):return false
			if obj.has("guest_remove") and (field!="objects" or not obj.guest_remove is bool or not obj.guest_remove
					or obj.type not in preload("res://scripts/plot_permissions.gd").SHARED_REMOVAL_FURNITURE or obj.get("aru_public",false)):return false
			if obj.has("aru_public"):
				var slots:Dictionary=preload("res://scripts/resident_goals.gd").ARU_PARK_SLOTS
				if field!="objects" or not obj.aru_public is bool or not obj.aru_public or not slots.has(obj.type):return false
				var slot:Vector2i=slots[obj.type]
				if tile!="%d,%d"%[slot.x,slot.y]:return false
			if obj.has("loom_part") and obj.type!="loom":return false
			if obj.has("furnace_part") and obj.type!="glass_furnace":return false
			if obj.has("kiln_part") and obj.type!=Industry.CLAY_KILN:return false
			if obj.has("collector_count") or obj.has("collector_animal") or obj.has("collector_count_quality") or obj.has("collector_items"):
				if field!="objects" or obj.type!=Industry.ANIMAL_COLLECTOR or not obj.get("collector_animal") is String:return false
				if obj.collector_animal==AnimalCollector.PEN:
					# C24 pen-bound basket: per-item counts only. Enclosure topology and other
					# collectors are not validated, because walls change after binding.
					if not whole(obj.get("collector_count"),AnimalCollector.CAPACITY) or not AnimalCollector.valid_pen_basket(obj):return false
				else:
					if obj.has("collector_items"):return false
					var coords:=tile.split(",")
					var cell:=Vector2i(int(coords[0]),int(coords[1]))
					if not AnimalCollector.in_range(cell,obj.collector_animal) or not whole(obj.get("collector_count"),AnimalCollector.CAPACITY):return false
					if obj.has("collector_count_quality"):
						if not whole(obj.collector_count_quality,int(obj.collector_count)):return false
					if AnimalCollector.bound_elsewhere(s.objects,obj.collector_animal,tile):return false
				obj.collector_count=int(obj.collector_count)
			if obj.type=="table" and obj.items.keys().any(func(item):return item in Industry.WOOD_TABLE_DISPLAY):
				if field!="objects" or obj.items.size()!=1 or int(obj.items.values()[0])!=1:return false
			if obj.type in [Industry.MUSHROOM_STOOL,Industry.HEDGEHOG_BASKET] and (field!="objects" or not obj.items.is_empty()):return false
			if obj.type==Industry.SHELL_TABLE:
				if field!="objects" or obj.items.size()>1:return false
				for item in obj.items:
					if not ItemCatalog.is_known(item) or not whole(obj.items[item],1) or int(obj.items[item])!=1:return false
			if obj.type==Industry.ANIMAL_COLLECTOR and (field!="objects" or not obj.items.is_empty()):return false
			if obj.has("dye") and (field!="objects" or obj.type not in Industry.DYEABLE_FURNITURE or not obj.dye is String or not Industry.FURNITURE_DYES.has(obj.dye)):return false
			if obj.has("dye_part") and obj.type!=Industry.DYE_TABLE:return false
			if obj.has("assembly_part") and obj.type!=Industry.ASSEMBLY_TABLE:return false
			if obj.has("stone_bench_part") and obj.type!=Industry.STONE_WORKBENCH:return false
			if obj.has(Industry.KITCHEN_STOVE_PART) and obj.type!=Industry.KITCHEN_STOVE:return false
			if obj.has("stone_bench_vertical") and (obj.type!=Industry.STONE_WORKBENCH or not obj.stone_bench_vertical is bool):return false
			if obj.has("screen_part") and obj.type!=Industry.FABRIC_SCREEN:return false
			if obj.has("screen_vertical") and (obj.type!=Industry.FABRIC_SCREEN or not obj.screen_vertical is bool):return false
			if obj.has("bath_part") and obj.type!=Industry.FOOT_BATH:return false
			if obj.has("bath_vertical") and (obj.type!=Industry.FOOT_BATH or not obj.bath_vertical is bool):return false
			if obj.has("luggage_part") and obj.type!=Industry.LUGGAGE_RACK:return false
			if obj.has("luggage_vertical") and (obj.type!=Industry.LUGGAGE_RACK or not obj.luggage_vertical is bool):return false
			if obj.has(MUSHROOM_MAIL.RECORD) or (obj.type in [Industry.MUSHROOM_POST,Industry.QUIET_BIRDHOUSE] and (field!="objects" or not obj.items.is_empty())):return false
			if obj.has("leaf_desk_part") and obj.type!=Industry.LEAF_DESK:return false
			if obj.has("leaf_desk_vertical") and (obj.type!=Industry.LEAF_DESK or not obj.leaf_desk_vertical is bool):return false
			if obj.has(Industry.DESK_DRAFT_FIELD):return false
			if obj.has("observation_part") and obj.type!=Industry.OBSERVATION_DESK:return false
			if obj.has("observation_vertical") and (obj.type!=Industry.OBSERVATION_DESK or not obj.observation_vertical is bool):return false
			if obj.has("seed_cabinet_part") and obj.type!=Industry.SEED_CABINET:return false
			if obj.has("seed_cabinet_vertical") and (obj.type!=Industry.SEED_CABINET or not obj.seed_cabinet_vertical is bool):return false
			if obj.has("nursery_box_part") and obj.type!=Industry.NURSERY_BOX:return false
			if obj.has("fish_counter_part") and obj.type!=Industry.COAST_FISH_COUNTER:return false
			if obj.has("fish_counter_vertical") and (obj.type!=Industry.COAST_FISH_COUNTER or not obj.fish_counter_vertical is bool):return false
			if obj.has("tea_cabinet_part") and obj.type!=Industry.TEA_DISPLAY_CABINET:return false
			if obj.has("tea_cabinet_vertical") and (obj.type!=Industry.TEA_DISPLAY_CABINET or not obj.tea_cabinet_vertical is bool):return false
			if obj.has("awning_part") and obj.type!=Industry.COAST_AWNING:return false
			if obj.has("awning_vertical") and (obj.type!=Industry.COAST_AWNING or not obj.awning_vertical is bool):return false
			# C13: a legacy 1x1 mill has neither field. A new 3x3 mill carries `mill_part` 0..8 and the same
			# `mill_facing` 0..3 on all nine cells (the nine-cell group is verified in the footprint block below).
			if obj.has(Industry.MILL_PART) and (obj.type!=Industry.MILL or field!="objects"):return false
			if obj.has(Industry.MILL_FACING) and (obj.type!=Industry.MILL or not obj.has(Industry.MILL_PART) or not whole(obj[Industry.MILL_FACING],Industry.MILL_FACING_COUNT-1)):return false
			if obj.has(Industry.MILL_PART) and not obj.has(Industry.MILL_FACING):return false
			if obj.has("imperfect_pavilion_part") and obj.type!=Industry.IMPERFECT_TEA_PAVILION:return false
			if obj.has("imperfect_pavilion_vertical"):return false
			if obj.has("market_cart_part") and obj.type!=Industry.COAST_CART:return false
			if obj.has("market_cart_open") and (field!="objects" or obj.type!=Industry.COAST_CART or Industry.square_part(obj)!=0 or not obj.market_cart_open is bool or not obj.market_cart_open):return false
			if obj.has("register_part") and obj.type!=Industry.COAST_REGISTER:return false
			if obj.has("register_vertical") and (obj.type!=Industry.COAST_REGISTER or not obj.register_vertical is bool):return false
			if obj.has("rounded_table_part") and obj.type!=Industry.ROUNDED_TABLE:return false
			if obj.has("rounded_table_vertical") and (obj.type!=Industry.ROUNDED_TABLE or not obj.rounded_table_vertical is bool):return false
			if obj.has("bookcase_part") and obj.type!=Industry.GRID_BOOKCASE:return false
			if obj.has("cedar_bed_part") and obj.type!=Industry.CEDAR_BED:return false
			if obj.has("cedar_bed_vertical") and (obj.type!=Industry.CEDAR_BED or not obj.cedar_bed_vertical is bool):return false
			if obj.has("bookcase_vertical") and (obj.type!=Industry.GRID_BOOKCASE or not obj.bookcase_vertical is bool):return false
			if obj.has("tool_board_part") and obj.type!=WALL_FIXTURES.TOOL_BOARD:return false
			if obj.has("tool_board_vertical"):return false
			if obj.has(WALL_FIXTURES.TOOL_BOARD_FIELD):
				if obj.type!=WALL_FIXTURES.TOOL_BOARD or Industry.square_part(obj)!=0 or not WALL_FIXTURES.valid_tool_board_tools(obj[WALL_FIXTURES.TOOL_BOARD_FIELD]):return false
			if obj.has("riverside_screen_part") and obj.type!=Industry.RIVERSIDE_SCREEN:return false
			if obj.has("riverside_screen_vertical") and (obj.type!=Industry.RIVERSIDE_SCREEN or not obj.riverside_screen_vertical is bool):return false
			if obj.has(Industry.RIVERSIDE_FOLDED_FIELD) and (field!="objects" or obj.type!=Industry.RIVERSIDE_SCREEN or typeof(obj[Industry.RIVERSIDE_FOLDED_FIELD])!=TYPE_BOOL or not obj[Industry.RIVERSIDE_FOLDED_FIELD]):return false
			if obj.has("beach_chair_part") and obj.type!=Industry.BEACH_CHAIR:return false
			if obj.has("beach_chair_vertical") and (obj.type!=Industry.BEACH_CHAIR or not obj.beach_chair_vertical is bool):return false
			if obj.has("beach_chair_folded") and (obj.type!=Industry.BEACH_CHAIR or not obj.beach_chair_folded is bool):return false
			if obj.has("bamboo_lounger_part") and obj.type!=Industry.BAMBOO_LOUNGER:return false
			if obj.has("bamboo_lounger_vertical") and (obj.type!=Industry.BAMBOO_LOUNGER or not obj.bamboo_lounger_vertical is bool):return false
			if obj.has("nursery_box_vertical") and (obj.type!=Industry.NURSERY_BOX or not obj.nursery_box_vertical is bool):return false
			if obj.has("nursery_slots"):
				if field!="objects" or obj.type!=Industry.NURSERY_BOX or Industry.square_part(obj)!=0 or not nursery_slots_valid(obj.nursery_slots,crops):return false
			if obj.has("aquarium_part") and obj.type!=Industry.AQUARIUM:return false
			if obj.has("aquarium_vertical") and (obj.type!=Industry.AQUARIUM or not obj.aquarium_vertical is bool):return false
			if obj.has("glass_table_part") and obj.type!=Industry.GLASS_FLOWER_TABLE:return false
			if obj.has("glass_table_vertical") and (obj.type!=Industry.GLASS_FLOWER_TABLE or not obj.glass_table_vertical is bool):return false
			if obj.has("leaf_mat_part") and obj.type!=Industry.LEAF_MAT:return false
			if obj.has("braided_rug_part") and obj.type!=Industry.BRAIDED_RUG:return false
			if obj.has("lamp_off") and (obj.type not in Industry.SWITCHABLE_LAMPS or field!="objects" or not obj.lamp_off is bool):return false
			if obj.has("leaf_mat_shade"):
				if obj.type!=Industry.LEAF_MAT or field!="ground" or not obj.leaf_mat_shade is String or not Industry.MAT_SHADES.has(obj.leaf_mat_shade):return false
			if obj.has("forest_arch_part") and obj.type!=Industry.FOREST_ARCH:return false
			if obj.has("forest_arch_vertical") and (obj.type!=Industry.FOREST_ARCH or not obj.forest_arch_vertical is bool):return false
			if obj.has("vine_arch_part") and obj.type!=Industry.VINE_ARCH:return false
			if obj.has("vine_arch_vertical") and (obj.type!=Industry.VINE_ARCH or not obj.vine_arch_vertical is bool):return false
			if obj.has("copper_rack_part") and obj.type!=Industry.POT_RACK:return false
			if obj.has("copper_rack_vertical") and (obj.type!=Industry.POT_RACK or not obj.copper_rack_vertical is bool):return false
			if obj.has("rack_pots"):
				if obj.type!=Industry.POT_RACK or field!="objects" or Industry.square_part(obj)!=0 or not Industry.valid_rack_pots(obj.rack_pots):return false
			if obj.has("vine_color"):
				if obj.type!=Industry.VINE_ARCH or field!="objects" or Industry.square_part(obj)!=0 or not obj.vine_color is String or not Industry.VINE_COLORS.has(obj.vine_color):return false
			if obj.has(Industry.SEED_SAMPLES):
				if obj.type!=Industry.SEED_CABINET or field!="objects" or Industry.square_part(obj)!=0:return false
				var samples:Variant=obj[Industry.SEED_SAMPLES]
				if not samples is Array or samples.is_empty() or samples.size()>Industry.SEED_SAMPLE_SLOTS:return false
				var known:Dictionary=s.players.get(obj.owner,{}).get("collection",{}).get("crops",{})
				var seen:Dictionary={}
				for crop in samples:
					if not crop is String or not known.has(crop) or seen.has(crop):return false
					seen[crop]=true
			if obj.has("mushroom_table_part") and obj.type!=Industry.MUSHROOM_TABLE:return false
			if obj.has("bamboo_tea_table_part") and obj.type!=Industry.BAMBOO_TEA_TABLE:return false
			if obj.has("bamboo_tea_table_vertical") and (obj.type!=Industry.BAMBOO_TEA_TABLE or not obj.bamboo_tea_table_vertical is bool):return false
			if obj.has(Industry.TEA_SET_FIELD):
				if obj.type!=Industry.BAMBOO_TEA_TABLE or field!="objects" or Industry.square_part(obj)!=0 or typeof(obj[Industry.TEA_SET_FIELD])!=TYPE_BOOL or not obj[Industry.TEA_SET_FIELD]:return false
			if obj.has("hollow_bed_part") and obj.type!=Industry.HOLLOW_BED:return false
			if obj.has("inn_bed_part") and obj.type!=Industry.INN_BED:return false
			if obj.has("inn_bed_vertical") and (obj.type!=Industry.INN_BED or not obj.inn_bed_vertical is bool):return false
			if obj.type==Industry.INN_BED and obj.has("dye") and Industry.square_part(obj)>0:return false
			if obj.has("assembly_vertical") and (obj.type!=Industry.ASSEMBLY_TABLE or obj.assembly_vertical!=true or typeof(obj.assembly_vertical)!=TYPE_BOOL):return false
			if obj.has("dye_vertical") and (obj.type!=Industry.DYE_TABLE or obj.dye_vertical!=true or typeof(obj.dye_vertical)!=TYPE_BOOL):return false
			# C08: a legacy 1x1 bench has neither field and is left alone. A wide bench must carry the
			# part marker on every cell, and an orientation flag is only valid with it.
			if obj.has(Industry.WORKBENCH_PART) and obj.type!=Industry.WORKBENCH:return false
			if obj.has(Industry.WORKBENCH_VERTICAL) and (obj.type!=Industry.WORKBENCH or not obj.has(Industry.WORKBENCH_PART) or typeof(obj[Industry.WORKBENCH_VERTICAL])!=TYPE_BOOL):return false
			if obj.has(Industry.WORKBENCH_PART) and typeof(obj[Industry.WORKBENCH_PART])!=TYPE_INT and typeof(obj[Industry.WORKBENCH_PART])!=TYPE_FLOAT:return false
			if obj.type in Industry.FIXED_SQUARE_STATIONS or obj.type in Industry.ORIENTABLE_FOOTPRINTS or obj.has("loom_part") or obj.has("furnace_part") or obj.has(Industry.WORKBENCH_PART) or obj.has(Industry.MILL_PART):
				var part_field:=Industry.square_part_field(obj.type)
				var fallback:=0 if obj.type==Industry.SMELTER else -1
				var station_cells:=Industry.station_cells(obj.type,Industry.is_vertical(obj))
				var station_layer:="ground" if obj.type==Industry.LEAF_MAT else "objects"
				if field!=station_layer or not whole(obj.get(part_field,fallback),station_cells.size()-1):return false
				var part:=int(obj.get(part_field,fallback))
				if obj.type==Industry.LEAF_MAT and part!=0 and obj.has("leaf_mat_shade"):return false
				if obj.type==Industry.AQUARIUM and not obj.items.is_empty():
					if part!=0 or obj.items.size()!=1 or not whole(obj.items.get(Industry.AQUARIUM_FISH),1) or int(obj.items[Industry.AQUARIUM_FISH])!=1:return false
				elif obj.type==Industry.COAST_FISH_COUNTER and not obj.items.is_empty():
					if part!=0 or obj.items.size()>Industry.COUNTER_CAPACITY:return false
					for fish in obj.items:
						if not Collections.FISH.has(fish) or not whole(obj.items[fish],1) or int(obj.items[fish])!=1:return false
				elif obj.type==Industry.TEA_DISPLAY_CABINET and not obj.items.is_empty():
					if part!=0 or not Industry.valid_tea_cabinet_items(obj.items):return false
					for tea:String in obj.items.keys():
						if not ItemCatalog.is_known(tea):return false
						obj.items[tea]=int(obj.items[tea])
				elif obj.type==Industry.ROUNDED_TABLE and not obj.items.is_empty():
					if part!=0 or Industry.rounded_table_count(obj.items)>Industry.ROUNDED_CAPACITY:return false
					for item:String in obj.items:
						if not Industry.rounded_table_item(item,recipes) or int(obj.items[item])<1:return false
				elif obj.type in Industry.FOUR_SEAT_TABLES and not obj.items.is_empty():
					if part!=0:return false
					var portions:=0
					for item:String in obj.items:
						if not Industry.four_seat_meal(obj.type,item,recipes) or not whole(obj.items[item],Industry.MUSHROOM_TABLE_CAPACITY) or int(obj.items[item])<1:return false
						portions+=int(obj.items[item])
					if portions>Industry.MUSHROOM_TABLE_CAPACITY:return false
				elif obj.type==Industry.MILL:
					# C13: only the anchor may hold output (its own cap is checked with the processor buffers).
					if part>0 and not obj.items.is_empty():return false
				elif not obj.items.is_empty():
					if obj.type!=Industry.LUGGAGE_RACK or part!=0:return false
					var shown:=0
					for item in obj.items:
						if not ItemCatalog.is_known(item) or not whole(obj.items[item],Industry.LUGGAGE_SLOTS) or int(obj.items[item])<1:return false
						shown+=int(obj.items[item])
					if shown>Industry.LUGGAGE_SLOTS:return false
				if obj.has(part_field):obj[part_field]=part
				if obj.type==Industry.MILL:
					if field!="objects" or not obj.has(part_field) or not obj.has(Industry.MILL_FACING):return false
					obj[Industry.MILL_FACING]=int(obj[Industry.MILL_FACING])
					# Cells 1..8 are never a second machine: no buffer or switch (job/processing are rejected below).
					if part>0 and (obj.has("input_wheat") or obj.has("auto_enabled")):return false
				var xy:=tile.split(",")
				var anchor:Vector2i=Vector2i(int(xy[0]),int(xy[1]))-station_cells[part]
				if part>0 and (obj.has("processing") or obj.has("job") or obj.has("cooking")):return false
				if part==0 and obj.type=="loom" and obj.get("joinery_loom")!=true:return false
				if part==0 and obj.type=="glass_furnace" and obj.get("iron_furnace")!=true:return false
				for index in station_cells.size():
					var spot:Vector2i=anchor+station_cells[index]
					var other=s[field].get("%d,%d"%[spot.x,spot.y])
					if not other is Dictionary or other.get("type")!=obj.type or other.get("owner")!=obj.owner:return false
					var other_part:Variant=other.get(part_field,fallback)
					if not whole(other_part,station_cells.size()-1) or int(other_part)!=index or Industry.is_vertical(other)!=Industry.is_vertical(obj):return false
					if obj.type==Industry.MILL and (not whole(other.get(Industry.MILL_FACING),Industry.MILL_FACING_COUNT-1) or int(other[Industry.MILL_FACING])!=int(obj[Industry.MILL_FACING])):return false
					if obj.type==Industry.BEACH_CHAIR and other.get("beach_chair_folded",false)!=obj.get("beach_chair_folded",false):return false
					if obj.type==Industry.RIVERSIDE_SCREEN and other.get(Industry.RIVERSIDE_FOLDED_FIELD,false)!=obj.get(Industry.RIVERSIDE_FOLDED_FIELD,false):return false
			if obj.get("type") in preload("res://scripts/resident_goals.gd").DOUBLE_BENCHES:
				if field!="objects" or not obj.items.is_empty():return false
				var coords:=tile.split(",")
				var is_end:bool=obj.get("bench_end",false)==true
				if obj.has("bench_end") and not obj.bench_end is bool:return false
				var vertical:bool=obj.get("bench_vertical",false)==true
				if obj.has("bench_vertical") and not obj.bench_vertical is bool:return false
				var step:=-1 if is_end else 1
				var partner_key:="%d,%d"%[int(coords[0])+(0 if vertical else step),int(coords[1])+(step if vertical else 0)]
				var partner=s[field].get(partner_key)
				if not partner is Dictionary or partner.get("type")!=obj.type or partner.get("owner")!=obj.owner or partner.get("bench_end",false)==is_end or partner.get("bench_vertical",false)!=vertical:return false
				if is_end and obj.has("inscription"):return false
			if obj.has("bell_at") and (field!="objects" or obj.type not in preload("res://scripts/resident_goals.gd").FESTIVAL_BELL_KINDS or not number(obj.bell_at,0,float(s.time))):return false
			if obj.has(BARK_FRAME.FIELD) and (obj.type!=WALL_FIXTURES.BARK_FRAME or not BARK_FRAME.valid_display(obj[BARK_FRAME.FIELD])):return false
			if obj.type in WALL_FIXTURES.KINDS:
				if field!="objects":return false
				if obj.type in [WALL_FIXTURES.LIFEBUOY,WALL_FIXTURES.BARK_FRAME,WALL_FIXTURES.HOME_SIGN,WALL_FIXTURES.BAMBOO_CURTAIN] and not obj.items.is_empty():return false
				var coords:=tile.split(",")
				# Undo records only contain changed cells. World checks attachment support on restoration.
				if not partial_history and not WALL_FIXTURES.has_support(s[field],Vector2i(int(coords[0]),int(coords[1])),str(obj.owner),str(obj.type),s.get("edges",{})):return false
			if obj.has(POSTCARDS.SLOTS):
				if field!="objects" or obj.type!=POSTCARDS.RACK or not POSTCARDS.valid_display(obj[POSTCARDS.SLOTS]):return false
				if not partial_history:
					var earned:=POSTCARDS.earned(s.players.get(obj.owner,{}))
					for card_id:String in obj[POSTCARDS.SLOTS]:
						if card_id not in earned:return false
			if obj.type==POSTCARDS.RACK and (field!="objects" or not obj.items.is_empty()):return false
			if obj.has(OAR_SIGN.FIELD) and (obj.type!=OAR_SIGN.KIND or field!="objects" or not location(obj[OAR_SIGN.FIELD],size)):return false
			if obj.type==OAR_SIGN.KIND and (field!="objects" or not obj.items.is_empty()):return false
			if obj.type==ROOF_FIXTURES.HANGING_POT:
				if field!="objects" or not obj.get("items",{}).is_empty():return false
				if not partial_history and not ROOF_FIXTURES.supported(s.get("roofs",{}).get(tile),str(obj.owner)):return false
			if obj.has("inscription") and (field!="objects" or obj.type not in ["sign","long_bench","master_bench"] or not preload("res://scripts/resident_goals.gd").valid_inscription(obj.inscription) or obj.inscription.is_empty()):return false
			if obj.has("welcome") and (field!="objects" or obj.type not in [WELCOME_SIGN.KIND,WALL_FIXTURES.HOME_SIGN] or not WELCOME_SIGN.valid(obj.welcome)):return false
			if obj.type=="inn_tea_table" and not obj.items.is_empty():
				var cups:=0
				for tea in obj.items:
					if tea not in ["mist_tea_brew","ginger_tea"] or not whole(obj.items[tea],2) or obj.items[tea]<1:return false
					cups+=int(obj.items[tea])
				if cups>2:return false
			if obj.has("style") and (not obj.style is String or BUILD_STYLES.entry(obj.style+"."+obj.type).is_empty()):return false
			if obj.type in ["author_sign","author_shelf","expedition_tent",WALL_FIXTURES.HOME_SIGN] and (not obj.get("author") is String or obj.author.length()>12):return false
			if field=="ground" and obj.type not in ["floor","stone_floor","path","spring_pebble_path",Industry.LEAF_MAT]:return false
			if field=="roofs" and obj.type not in ["roof","greenhouse_roof",preload("res://scripts/greenhouse_glass.gd").XINGHE_ROOF,preload("res://scripts/terracotta_roof.gd").KIND]:return false
			if field=="objects" and obj.type in ["floor","stone_floor","path","spring_pebble_path",Industry.LEAF_MAT,"roof","greenhouse_roof",preload("res://scripts/greenhouse_glass.gd").XINGHE_ROOF,preload("res://scripts/terracotta_roof.gd").KIND]:return false
			if obj.type=="conveyor":
				conveyor_owners[obj.owner]=int(conveyor_owners.get(obj.owner,0))+1
				if conveyor_owners[obj.owner]>Logistics.BELT_LIMIT:return false
				if not whole(obj.get("dir"),3) or not obj.get("enabled") is bool or obj.get("filter") not in Logistics.FILTERS:return false
				if not obj.items.is_empty() and (obj.items.size()!=1 or obj.items.get(obj.filter)!=1):return false
			# Version 24: the mill and its `input_wheat` buffer are forward state for
			# any older save; input_wheat never appears on another object type.
			if obj.type in BAKERY_STATIONS and not bakery_ok(s):return false
			if obj.has("input_wheat") and obj.type!="mill":return false
			if obj.type in Logistics.PROCESSORS and Industry.is_mill_extension(obj):
				# C13: the eight extra cells of a new mill hold nothing (also covered above for job/processing).
				if not obj.items.is_empty() or obj.has("auto_enabled") or obj.has("input_wheat") or obj.has("job") or obj.has("processing"):return false
			elif obj.type in Logistics.PROCESSORS:
				var input_key:=Logistics.input_field(obj.type)
				for other in Logistics.INPUT_FIELDS:
					if other!=input_key and obj.has(other):return false
				# Additive defaults only for the legacy wood stations; a v24 mill
				# must carry its own buffer fields.
				if obj.type in ["sawmill","charcoal_kiln"]:
					if not obj.has(input_key):obj[input_key]=0
					if not obj.has("auto_enabled"):obj.auto_enabled=false
				if not obj.has(input_key) or not obj.has("auto_enabled"):return false
				if not whole(obj[input_key],Logistics.PROCESS_INPUT_CAP) or not obj.auto_enabled is bool:return false
				var output:=Logistics.output_item(obj.type)
				if not obj.items.is_empty() and (obj.items.size()!=1 or not whole(obj.items.get(output),Logistics.PROCESS_OUTPUT_CAP)):return false
			if obj.type=="forester":
				forestry_owners[obj.owner]=int(forestry_owners.get(obj.owner,0))+1
				if forestry_owners[obj.owner]>Forestry.LIMIT:return false
				if not obj.get("enabled") is bool or not whole(obj.get("fuel"),Forestry.CAPACITY) or not whole(obj.get("saplings"),Forestry.CAPACITY):return false
				if not whole(obj.get("cursor"),Forestry.OFFSETS.size()-1):return false
				if not number(obj.get("next_cycle"),0,float(s.time)+Forestry.INTERVAL):return false
				if not number(obj.get("last_cycle"),-1,float(s.time)) or (float(obj.last_cycle)<0 and float(obj.last_cycle)!=-1):return false
				for item in obj.items:
					if not Forestry.OUTPUT_CAPS.has(item) or not whole(obj.items[item],Forestry.OUTPUT_CAPS[item]) or int(obj.items[item])==0:return false
			if Industry.LIMITS.has(obj.type):
				var counter_key:=[obj.type,obj.owner]
				industry_owners[counter_key]=int(industry_owners.get(counter_key,0))+1
				if industry_owners[counter_key]>Industry.LIMITS[obj.type] or not obj.items.is_empty():return false
			if obj.type=="mine_drill":
				if not obj.get("enabled") is bool or not whole(obj.get("fuel"),MineDrill.FUEL_CAP) or not whole(obj.get("dir"),3):return false
			if obj.type=="waterworks":
				if not obj.get("enabled") is bool or not whole(obj.get("water"),Waterworks.CAPACITY):return false
				if not obj.get("input") is Dictionary or obj.input.size()!=Waterworks.INPUTS.size():return false
				for material in Waterworks.INPUTS:
					if not whole(obj.input.get(material),Waterworks.INPUT_CAP):return false
				if not obj.items.is_empty() and (obj.items.size()!=1 or not whole(obj.items.get("copper_joint"),Waterworks.OUTPUT_CAP) or obj.items.copper_joint<1):return false
			if obj.type=="water_tank":
				if not whole(obj.get("water"),Industry.TANK_CAPACITY):return false
			if obj.type=="water_pump" and not obj.get("enabled") is bool:return false
			# 第 40 章分流閘（不升版）：mode 必須是 open/low/closed。
			if obj.type==Industry.GATE_KIND and obj.get("mode") not in Industry.GATE_MODES:return false
			# 第 40 章水塔（不升版）：只有 type/owner/items/water/enabled（＋可選 style），
			# water 為 0..TOWER_CAPACITY 的整數、enabled 為 bool；items 必須是空的（LIMITS 檢查）。
			if obj.type==Industry.TOWER_KIND:
				for field_name in obj:
					if str(field_name) not in ["type","owner","items","water","enabled","style","reserve","quota","quota_day","quota_used"]:return false
				if not whole(obj.get("water"),Industry.TOWER_CAPACITY) or not obj.get("enabled") is bool:return false
				# 定量配水（可省略）：reserve／quota 只能是面板上的非零選項；quota_day／quota_used
				# 只能和 quota 一起出現，日期不晚於今天。
				if obj.has("reserve") and (not whole(obj.reserve,48) or int(obj.reserve)==0 or int(obj.reserve) not in Industry.TOWER_RESERVES):return false
				if obj.has("quota"):
					if not whole(obj.quota,Industry.TOWER_QUOTA_MAX) or int(obj.quota)==0 or int(obj.quota) not in Industry.TOWER_QUOTAS:return false
					if not whole(obj.get("quota_day"),floorf(float(s.time)/Industry.TOWER_DAY)) or not whole(obj.get("quota_used"),Industry.TOWER_QUOTA_MAX):return false
				elif obj.has("quota_day") or obj.has("quota_used"):return false
			if obj.has("iron_furnace") and (obj.type!="glass_furnace" or typeof(obj.iron_furnace)!=TYPE_BOOL or not obj.iron_furnace):return false
			if obj.has("wood_window") and (obj.type!="window" or typeof(obj.wood_window)!=TYPE_BOOL or not obj.wood_window):return false
			if obj.has("joinery_loom") and (obj.type!="loom" or typeof(obj.joinery_loom)!=TYPE_BOOL or not obj.joinery_loom):return false
			if obj.has("joinery_seed_maker") and (obj.type!="seed_maker" or typeof(obj.joinery_seed_maker)!=TYPE_BOOL or not obj.joinery_seed_maker):return false
			if obj.has("ceramic_pot") and (obj.type!="jam_pot" or typeof(obj.ceramic_pot)!=TYPE_BOOL or not obj.ceramic_pot):return false
			if obj.type=="large_sprinkler" and obj.get("sprinkler_daily")!=true:return false
			if obj.has("assembled_sprinkler") and (not Industry.SPRINKLER_KITS.has(obj.type) or typeof(obj.assembled_sprinkler)!=TYPE_BOOL or not obj.assembled_sprinkler or obj.get("sprinkler_daily")!=true):return false
			if obj.has(Industry.STARTER_SPRINKLER_FIELD):
				if obj.type!="sprinkler" or not obj[Industry.STARTER_SPRINKLER_FIELD] is bool or not obj[Industry.STARTER_SPRINKLER_FIELD]:return false
				if obj.get("sprinkler_daily")!=true or obj.has("assembled_sprinkler"):return false
			if obj.has("sprinkler_daily") and (obj.type not in ["sprinkler","medium_sprinkler","large_sprinkler"] or typeof(obj.sprinkler_daily)!=TYPE_BOOL or not obj.sprinkler_daily):return false
			if Industry.SPRINKLER_CAPACITIES.has(obj.type):
				if not whole(obj.get("water"),Industry.SPRINKLER_CAPACITIES[obj.type]) or not obj.get("enabled") is bool:return false
				if obj.has("network_water") and not whole(obj.network_water, float(obj.water)):return false
				var day_seconds:=Weather.DAY_SECONDS
				var next_limit:=float(s.time)+8.0
				if obj.get("sprinkler_daily",false):next_limit=(floorf(float(s.time)/day_seconds)+1.0)*day_seconds
				if not number(obj.get("next_water"),0,next_limit) or not number(obj.get("last_water"),-1,float(s.time)):return false
				if float(obj.last_water)<0 and float(obj.last_water)!=-1:return false
				var sprinkler_key:=[obj.owner,obj.type]
				sprinkler_owners[sprinkler_key]=int(sprinkler_owners.get(sprinkler_key,0))+1
				if sprinkler_owners[sprinkler_key]>Industry.SPRINKLER_LIMIT:return false
			if obj.has("freight_id") and (obj.type!="private_chest" or not Freight.valid_id(obj.freight_id)):return false
			if obj.has(CHEST_HISTORY.FIELD):
				if field!="objects" or not CHEST_HISTORY.valid(obj, ItemCatalog.is_known):return false
				CHEST_HISTORY.normalize(obj)
			if obj.has("guest_deposit") and (obj.type!="private_chest" or not obj.guest_deposit is bool or not obj.guest_deposit):return false
			if obj.has("withdraw_guest"):
				var visitor=obj.withdraw_guest
				if field!="objects" or obj.type!="private_chest" or not owner(visitor) or visitor==obj.owner or not s.players.has(visitor):return false
			if obj.has("open") and not obj.open is bool:return false
			# s.version here is still the candidate's input version (projections
			# copy it; validate stamps VERSION only at the very end).
			if obj.has("cooking") and not cooking_valid(s,obj,recipes):return false
			if obj.type in Industry.MANUAL_STATIONS and (int(s.version)<26 or obj.has("job") or obj.has("auto_enabled") or not obj.items.is_empty()):return false
			if obj.has("processing") and not processing_valid(s,obj):return false
			if obj.has("box_id") and (field!="objects" or not box_id_valid(s,obj)):return false
			if obj.has("job"):
				var job=obj.job
				if not job is Dictionary:return false
				if obj.type=="mine_drill":
					if job.size()!=2 or job.get("owner")!=obj.owner or not number(job.get("ready"),MineDrill.DURATION,float(s.time)+MineDrill.DURATION):return false
					continue
				if obj.type=="waterworks":
					if job.size()!=2 or job.get("owner")!=obj.owner or not number(job.get("ready"),0,float(s.time)+Waterworks.DURATION):return false
					if int(obj.items.get("copper_joint",0))>=Waterworks.OUTPUT_CAP:return false
					continue
				if obj.type in Logistics.PROCESSORS:
					if job.has("auto") and not job.auto is bool:return false
					var recipe:Dictionary=Industry.PROCESS.get(job.get("kind"),{})
					if recipe.get("station","")!=obj.type or job.get("owner")!=obj.owner:return false
					if not number(job.get("ready"),0,float(s.time)+float(recipe.time)):return false
					if not whole(job.get("yield")) or int(job.yield)!=int(recipe.yield):return false
					if not counts(job.get("ingredients")) or job.ingredients!=recipe.ingredients:return false
					continue
				if obj.type!="stove" or not recipes.has(job.get("kind")):return false
				if job.kind in BAKERY_RECIPES and not bakery_ok(s):return false
				if not owner(job.get("owner")) or not number(job.get("ready")):return false
				if job.has("ingredients") and not counts(job.ingredients):return false
				if job.has("yield") and (not whole(job.yield) or int(job.yield)<1):return false
	for tree in s.forest.values():
		if not tree is Dictionary or not owner(tree.get("owner")) or not tree.get("mature") is bool:return false
		if not number(tree.get("growth"),0,tree_time):return false
		if tree.mature and float(tree.growth)<tree_time:return false
	for removed in s.removed.values():
		if not removed is bool:return false
	for damage in s.damage.values():
		if not whole(damage,3):return false
	if not s.has("animal"):s.animal={"bond":0,"egg_ready":-1.0,"last_pet":-30.0}
	if not s.has("livestock"):s.livestock={}
	if not s.livestock is Dictionary:return false
	var ranch=preload("res://scripts/livestock.gd")
	for id in s.livestock:
		var animal=s.livestock[id]
		if not ranch.ANIMALS.has(id) or not animal is Dictionary:return false
		for field in animal:
			if field not in ["feed","ready","next","bond","last_pet","last_care","follow_actor","collector","managed_pen","bonus_progress","ready_quality","collector_quality"]:return false
		if animal.has("follow_actor") and (id!="cow" or not animal.follow_actor is String or not s.players.has(animal.follow_actor) or not number(animal.get("last_pet"),0,float(s.time))):return false
		if animal.has("last_care") and (id!="sheep" or not animal.last_care is String or animal.last_care!="brush" or not animal.has("bond") or not animal.has("last_pet")):return false
		if animal.has("bonus_progress") and not whole(animal.bonus_progress,ranch.BONUS_INTERVAL):return false
		if animal.has("managed_pen") and not animal.managed_pen is bool:return false
		if animal.has("collector") and not whole(animal.collector,ranch.COLLECTOR_CAPACITY):return false
		if animal.has("bond") or animal.has("last_pet"):
			if not whole(animal.get("bond"),ranch.BOND_LIMIT) or not number(animal.get("last_pet"),0,float(s.time)):return false
		if not whole(animal.get("feed"),ranch.LIMIT) or not whole(animal.get("ready"),ranch.LIMIT):return false
		if animal.has("ready_quality") and not whole(animal.ready_quality,int(animal.ready)):return false
		if animal.has("collector_quality") and (not animal.has("collector") or not whole(animal.collector_quality,int(animal.collector))):return false
		if not number(animal.get("next"),-1.0):return false
		var running:bool=int(animal.feed)>0 and int(animal.ready)<ranch.LIMIT
		if (running and float(animal.next)<0.0) or (not running and float(animal.next)!=-1.0):return false
	if not s.animal is Dictionary or not whole(s.animal.get("bond")):return false
	if s.animal.has("hug_actor"):
		if not s.animal.hug_actor is String or not s.players.has(s.animal.hug_actor) or not number(s.animal.get("last_pet"),0,float(s.time)):return false
	if s.animal.has("feed_follow_actor"):
		if not s.animal.feed_follow_actor is String or not s.players.has(s.animal.feed_follow_actor):return false
	if s.animal.has("basket_eggs") and not whole(s.animal.basket_eggs,EGG_BASKET_CAPACITY):return false
	if s.animal.has("basket_eggs_quality") and (not s.animal.has("basket_eggs") or not whole(s.animal.basket_eggs_quality,int(s.animal.basket_eggs))):return false
	if s.animal.has("bonus_progress") and not whole(s.animal.bonus_progress,ranch.BONUS_INTERVAL):return false
	if not number(s.animal.get("egg_ready"),-1) or not number(s.animal.get("last_pet"),-30):return false
	if not s.has("picnic"):s.picnic=false
	if not s.picnic is bool:return false
	if not s.has("community"):s.community={"table":Community.choose_table(s) if s.picnic else ""}
	if not Community.valid(s):return false
	if s.has("public_fund"):
		var fund=s.public_fund
		if not fund is Dictionary or fund.size()!=2 or not whole(fund.get("balance")) or not fund.get("contributors") is Dictionary:return false
		var total:=0
		for actor in fund.contributors:
			if not s.players.has(actor) or not whole(fund.contributors[actor]) or int(fund.contributors[actor])<=0:return false
			total+=int(fund.contributors[actor])
		var spent:=total-int(fund.balance)
		if spent<0 or spent>230 or (spent>0 and not s.board):return false
	if not s.has("picnic_materials"):s.picnic_materials={"soup":0,"bread":0}
	if not s.picnic_materials is Dictionary:return false
	if not whole(s.picnic_materials.get("soup"),2) or not whole(s.picnic_materials.get("bread"),1):return false
	if not s.has("quarry"):s.quarry={"hits":0,"ready":0.0}
	if not s.has("seaweed_ready"):s.seaweed_ready=0.0
	if not number(s.seaweed_ready,0,float(s.time)+60.0):return false
	if not s.has("wangan_shell_ready"):s.wangan_shell_ready=0.0
	if not number(s.wangan_shell_ready,0,float(s.time)+preload("res://scripts/wangan_coast.gd").SHELL_RESPAWN):return false
	if not s.has("wangan_star_walk"):s.wangan_star_walk=false
	if not s.wangan_star_walk is bool:return false
	if not s.has("wangan_star_sand_ready"):s.wangan_star_sand_ready=0.0
	if not number(s.wangan_star_sand_ready,0,float(s.time)+preload("res://scripts/wangan_coast.gd").STAR_SAND_RESPAWN):return false
	if not s.wangan_star_walk and float(s.wangan_star_sand_ready)!=0.0:return false
	if not s.has("copper"):s.copper={"ready":0.0}
	if not s.copper is Dictionary or not number(s.copper.get("ready"),0,float(s.time)+12):return false
	if not s.quarry is Dictionary or not whole(s.quarry.get("hits"),2) or not number(s.quarry.get("ready")):return false
	if not s.has("festival"):s.festival=preload("res://scripts/festival.gd").fresh()
	var f=s.festival
	if not f is Dictionary or not whole(f.get("round")) or not f.get("active") is bool or not whole(f.get("collected"),12):return false
	if not f.get("contributors") is Dictionary or f.contributors.size()>12:return false
	var total:=0
	for who in f.contributors:
		if not s.players.has(who) or not whole(f.contributors[who],12) or int(f.contributors[who])<1:return false
		total+=int(f.contributors[who])
	if total!=int(f.collected):return false
	for field in ["started","finished","ready","best"]:
		if not number(f.get(field)):return false
	if f.active and (int(f.round)<1 or int(f.collected)>=12):return false
	if not f.active and int(f.collected) not in [0,12]:return false
	return true
