extends RefCounted
const ISLAND_NOTES=preload("res://scripts/island_notes.gd")
const OutlyingCommissions=preload("res://scripts/outlying_commissions.gd")
const IslandStoryRecap=preload("res://scripts/island_story_recap.gd")
const ResidentBond=preload("res://scripts/resident_bond.gd")
const BUILD_STYLES = preload("res://scripts/build_style_catalog.gd")

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
const Industry=preload("res://scripts/industry.gd")
const Forestry=preload("res://scripts/forestry.gd")
const Logistics=preload("res://scripts/logistics.gd")
const ConstructionHistory=preload("res://scripts/construction_history.gd")
const CookingQueue=preload("res://scripts/cooking_queue.gd")
const FlowerNursery=preload("res://scripts/flower_nursery.gd")
const SaltPan=preload("res://scripts/salt_pan.gd")
const OrderCatalog=preload("res://scripts/order_catalog.gd")
## No cycle: item_catalog.gd preloads nothing and reads World.NAMES via load().
const ItemCatalog=preload("res://scripts/item_catalog.gd")
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
## cutoffs below are literal and must NOT follow VERSION (salt <26, flowers <25, bakery <24,
## public kitchen <23, material box id <22, processing queue <21, cooking queue
## <20, blueprint history <19, undo history <18, auto roofs <17).
const VERSION:=26
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
const KITCHEN_SEAT_COUNT:=2
## Euclidean tile distances (inclusive), compared squared on integer cells.
const KITCHEN_STOVE_RANGE:=8
const KITCHEN_SEAT_RANGE:=3
const KITCHEN_STOVE_TYPE:="stove"
const KITCHEN_SEAT_TYPE:="long_bench"
const SeedMaker=preload("res://scripts/seed_maker.gd")
## T067 glass_furnace (no save bump): owner-only manual queue exactly like the
## loom (same version-26 rule, never `job`/`auto_enabled`/buffer items).
const PROCESSING_STATIONS:=["sawmill","charcoal_kiln","mill","seed_maker","loom","glass_furnace"]
const BOX_TYPES:=["chest","private_chest"]
const BOX_ID_LENGTH:=32

# Validate the parsed candidate before replacing a live world. Additive defaults
# migrate older prototype saves; invalid nested records never reach game code.
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

static func validate(s:Dictionary,crops:Dictionary,build:Dictionary,recipes:Dictionary,size:Vector2i,tree_time:float) -> bool:
	var version = s.get("version",0)
	if not whole(version,VERSION) or version < 1:return false
	if version == 1:
		if s.has("regions"):return false
		s.regions = {Regions.LANYANG:Regions.fresh()}
	if not s.get("regions") is Dictionary:return false
	# T067 deep floors B6–B15 have no save version of their own. A pre-current save
	# may only carry them as untouched empty layers; drop those before the
	# historical region-count checks and re-add them below.
	if int(version)<VERSION:
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
	# The public springs have no persistent tile edits. Older worlds load an
	# empty layer; visits and discoveries still use the existing player fields.
	for region in Regions.ANGLING_RESERVES:
		if not s.regions.has(region):s.regions[region]=Regions.fresh()
	# T067 deep floors B6–B15 (no version bump): they start empty and can only be
	# entered after mine_depths.unlocked passes 5, which Mines.valid checks below.
	for region in Regions.DEEP_MINES:
		if not s.regions.has(region):s.regions[region]=Regions.fresh()
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
	if not ISLAND_NOTES.valid(s.get("island_notes",[]),float(s.time)):return false
	if s.has("dock_stage") and not whole(s.dock_stage,2):return false
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
		for field in ["crops","objects","ground","roofs","forest","removed","damage"]:
			for key in local[field]:
				var parts: PackedStringArray = key.split(",")
				var tile := Vector2i(int(parts[0]),int(parts[1]))
				if not Regions.land(tile,region):return false
				if field not in ["removed","damage"] and (Regions.water(tile,region) or Regions.protected(tile,region)):return false
	if not discovery_groups_valid(s,{"fish":Collections.FISH,"crops":crops,"meals":recipes},true):return false
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
	if not stove is Dictionary or stove.get("type")!=KITCHEN_STOVE_TYPE:return false
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
	if obj.get("type")!="stove" or obj.has("job"):return false
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
		if recipe.get("station","")!=station:continue
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
			if not validate_region(projection,crops,build,recipes,size,tree_time):return false
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
			if not below is Dictionary or below.get("type")!="floor":return false
			if not s.players.has(roof.owner):return false
	return true

static func discovery_groups_valid(source:Dictionary,catalogs:Dictionary,island:bool) -> bool:
	for category in ["fish","crops","meals"]:
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

static func validate_region(s:Dictionary,crops:Dictionary,build:Dictionary,recipes:Dictionary,size:Vector2i,tree_time:float) -> bool:
	if not number(s.get("time")) or not whole(s.get("committed")) or not s.get("board") is bool:return false
	if not s.has("next_network_check"):s.next_network_check=0.0
	if not number(s.next_network_check,0,float(s.time)+Industry.INTERVAL):return false
	if not s.has("next_logistics_check"):s.next_logistics_check=0.0
	if not number(s.next_logistics_check,0,float(s.time)+Logistics.INTERVAL):return false
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
	for token in s.players:
		var personal = s.players[token]
		if personal is Dictionary and personal.has("news_seen") and not whole(personal.news_seen,ISLAND_NOTES.project_mask()):return false
		if personal is Dictionary and personal.has("ferry_recap_seen"):
			var marker:Variant=personal.ferry_recap_seen
			if not whole(marker,IslandStoryRecap.DOCK_STAGES|IslandStoryRecap.BIT_OPENED|IslandStoryRecap.BIT_BAMBOO):return false
			var stage:=int(marker)&3
			if stage>IslandStoryRecap.DOCK_STAGES or (int(marker)>3 and stage<IslandStoryRecap.DOCK_STAGES):return false
		if personal is Dictionary and personal.has("resident_participation"):
			var participation = personal.resident_participation
			if not participation is Dictionary or participation.size()>3:return false
			for event in participation:
				if event not in ["bridge","canal","shipment"] or participation[event]!=true:return false
		var p=s.players[token]
		if not owner(token) or not p is Dictionary or not p.get("name") is String:return false
		# T066 好感：可省略；存在時必須是已知居民的三個整數欄位。
		if p.has("bonds") and not ResidentBond.valid(p.bonds,float(s.time)):return false
		# T066「一起做的事」：可省略；存在時需為有行動的階、合法選項，且好感已到那一階。
		if p.has("bond_goals") and not preload("res://scripts/resident_goals.gd").valid(p.bond_goals,p):return false
		# T066 第三批紀念小物：可省略；存在時只能是已完成行動的紀念小物（值為 true）。
		if p.has("bond_keepsakes") and not preload("res://scripts/resident_goals.gd").valid_keepsakes(p.bond_keepsakes,p):return false
		if p.has("market") and not preload("res://scripts/market_stall.gd").valid(p.market,float(s.time),{}):return false # T071 市集攤位（可省略）
		if p.has("greenhouse_reported"):
			if not p.greenhouse_reported is bool:return false
			if p.greenhouse_reported and (p.get("greenhouse_glass_crafted")!=true or not crops.has(p.get("greenhouse_cross_season_crop",""))):return false
		if p.has("greenhouse_glass_crafted") and not p.greenhouse_glass_crafted is bool:return false
		if p.has("greenhouse_cross_season_crop") and (not p.greenhouse_cross_season_crop is String or not crops.has(p.greenhouse_cross_season_crop)):return false
		if p.name.length()>12 or not number(p.get("x"),0,size.x) or not number(p.get("y"),0,size.y):return false
		if not counts(p.get("inventory")) or not whole(p.get("coins")):return false
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
		if p.has("gathering_points") and not whole(p.gathering_points):return false
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
		if not Collections.validate(p, crops, recipes):return false
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
		if not p.orders.get("done") is Array or p.orders.done.size()>3:return false
		var seen:Dictionary={}
		for order in p.orders.done:
			if order not in ["radish","fish","bread"] or seen.has(order):return false
			seen[order]=true
		if not orders_active_valid(p.orders,float(s.time)):return false
		if not whole(p.trees_planted) or not whole(p.cooked):return false
		if p.has("fishing"):
			var fish=p.fishing
			if not fish is Dictionary or not whole(fish.get("x"),size.x-1) or not whole(fish.get("y"),size.y-1) or not number(fish.get("ready")):return false
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
		if c.has("owner") and not owner(c.owner):return false
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
		for obj in s[field].values():
			if not obj is Dictionary or not build.has(obj.get("type")) or not owner(obj.get("owner")) or not counts(obj.get("items")):return false
			if obj.has("style") and (not obj.style is String or BUILD_STYLES.entry(obj.style+"."+obj.type).is_empty()):return false
			if obj.type in ["author_sign","author_shelf","expedition_tent"] and (not obj.get("author") is String or obj.author.length()>12):return false
			if field=="ground" and obj.type not in ["floor","path"]:return false
			if field=="roofs" and obj.type not in ["roof","greenhouse_roof"]:return false
			if field=="objects" and obj.type in ["floor","path","roof","greenhouse_roof"]:return false
			if obj.type=="conveyor":
				conveyor_owners[obj.owner]=int(conveyor_owners.get(obj.owner,0))+1
				if conveyor_owners[obj.owner]>Logistics.BELT_LIMIT:return false
				if not whole(obj.get("dir"),3) or not obj.get("enabled") is bool or obj.get("filter") not in Logistics.FILTERS:return false
				if not obj.items.is_empty() and (obj.items.size()!=1 or obj.items.get(obj.filter)!=1):return false
			# Version 24: the mill and its `input_wheat` buffer are forward state for
			# any older save; input_wheat never appears on another object type.
			if obj.type in BAKERY_STATIONS and not bakery_ok(s):return false
			if obj.has("input_wheat") and obj.type!="mill":return false
			if obj.type in Logistics.PROCESSORS:
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
			if Industry.SPRINKLER_CAPACITIES.has(obj.type):
				if not whole(obj.get("water"),Industry.SPRINKLER_CAPACITIES[obj.type]) or not obj.get("enabled") is bool:return false
				if obj.has("network_water") and not whole(obj.network_water, float(obj.water)):return false
				if not number(obj.get("next_water"),0,float(s.time)+8) or not number(obj.get("last_water"),-1,float(s.time)):return false
				if float(obj.last_water)<0 and float(obj.last_water)!=-1:return false
				var sprinkler_key:=[obj.owner,obj.type]
				sprinkler_owners[sprinkler_key]=int(sprinkler_owners.get(sprinkler_key,0))+1
				if sprinkler_owners[sprinkler_key]>Industry.SPRINKLER_LIMIT:return false
			if obj.has("freight_id") and (obj.type!="private_chest" or not Freight.valid_id(obj.freight_id)):return false
			if obj.has("open") and not obj.open is bool:return false
			# s.version here is still the candidate's input version (projections
			# copy it; validate stamps VERSION only at the very end).
			if obj.has("cooking") and not cooking_valid(s,obj,recipes):return false
			if obj.type in ["seed_maker","loom","glass_furnace"] and (int(s.version)<26 or obj.has("job") or obj.has("auto_enabled") or not obj.items.is_empty()):return false
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
			if field not in ["feed","ready","next","bond","last_pet","collector","managed_pen","bonus_progress"]:return false
		if animal.has("bonus_progress") and not whole(animal.bonus_progress,ranch.BONUS_INTERVAL):return false
		if animal.has("managed_pen") and not animal.managed_pen is bool:return false
		if animal.has("collector") and not whole(animal.collector,ranch.COLLECTOR_CAPACITY):return false
		if animal.has("bond") or animal.has("last_pet"):
			if not whole(animal.get("bond"),ranch.BOND_LIMIT) or not number(animal.get("last_pet"),0,float(s.time)):return false
		if not whole(animal.get("feed"),ranch.LIMIT) or not whole(animal.get("ready"),ranch.LIMIT):return false
		if not number(animal.get("next"),-1.0):return false
		var running:bool=int(animal.feed)>0 and int(animal.ready)<ranch.LIMIT
		if (running and float(animal.next)<0.0) or (not running and float(animal.next)!=-1.0):return false
	if not s.animal is Dictionary or not whole(s.animal.get("bond")):return false
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
