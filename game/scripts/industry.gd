extends RefCounted

const SMELTER:="small_smelter"
const CLAY_KILN:="clay_kiln"
const DYE_TABLE:="dye_table"
const ASSEMBLY_TABLE:="assembly_table"
const FABRIC_SCREEN:="inn_fabric_screen"
const INN_BED:="inn_quilt_bed"
const FOOT_BATH:="inn_stone_footbath"
const LUGGAGE_RACK:="inn_luggage_rack"
const LUGGAGE_SLOTS:=2
const FOOT_BATH_SEATS:=[Vector2(0.57,0.67),Vector2(2.43,0.67),Vector2(0.57,1.48),Vector2(2.43,1.48)]
const ANIMAL_COLLECTOR:="animal_collector"
const ANIMAL_COLLECTOR_KIT:="animal_collector_kit"
const COLLECTOR_MATERIALS:={"iron_ingot":6,"woodwork_parts":4,"wood":12}
const TWO_CELL_STATIONS:=[DYE_TABLE,ASSEMBLY_TABLE,FABRIC_SCREEN,INN_BED,LUGGAGE_RACK]
const ORIENTABLE_FOOTPRINTS:=TWO_CELL_STATIONS+[FOOT_BATH]
const SPRINKLER_KITS:={"sprinkler":"field_sprinkler_kit","medium_sprinkler":"medium_sprinkler_kit","large_sprinkler":"large_sprinkler_kit"}
const DYEABLE_FURNITURE:=["chair","table","sofa","bed",INN_BED]
const FURNITURE_DYES:={"blue_dye":"藍染","orange_dye":"橙染"}
const DYE_REACH:=4
const FIXED_SQUARE_STATIONS:=[SMELTER,CLAY_KILN]
const MANUAL_STATIONS:=["seed_maker","loom","glass_furnace",SMELTER,"jam_pot",CLAY_KILN,DYE_TABLE]
const EXPANDABLE_STATIONS:=["loom","glass_furnace"]
const SQUARE_CELLS:=[Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]
const SMELTER_CELLS:=SQUARE_CELLS
const METAL_RECIPES:=["copper_ingot","iron_ingot"]

static func assembly_items() -> Dictionary:
	var items:=SPRINKLER_KITS.duplicate()
	items[ANIMAL_COLLECTOR]=ANIMAL_COLLECTOR_KIT
	return items

static func square_part_field(kind:String) -> String:
	if kind==FOOT_BATH:return "bath_part"
	if kind==LUGGAGE_RACK:return "luggage_part"
	return {"small_smelter":"smelter_part","loom":"loom_part","glass_furnace":"furnace_part","clay_kiln":"kiln_part","dye_table":"dye_part","assembly_table":"assembly_part",FABRIC_SCREEN:"screen_part",INN_BED:"inn_bed_part"}.get(kind,"")

static func square_part(obj:Dictionary) -> int:
	var kind:String=obj.get("type","")
	if kind in FIXED_SQUARE_STATIONS or kind in ORIENTABLE_FOOTPRINTS:return int(obj.get(square_part_field(kind),0))
	if kind in EXPANDABLE_STATIONS:return int(obj.get(square_part_field(kind),-1))
	return -1

static func vertical_field(kind:String) -> String:
	if kind==FABRIC_SCREEN:return "screen_vertical"
	if kind==INN_BED:return "inn_bed_vertical"
	if kind==FOOT_BATH:return "bath_vertical"
	if kind==LUGGAGE_RACK:return "luggage_vertical"
	return "assembly_vertical" if kind==ASSEMBLY_TABLE else "dye_vertical"

static func is_vertical(obj:Dictionary) -> bool:
	return obj.get(vertical_field(obj.get("type","")),false)==true

static func station_cells(kind:String,vertical:=false) -> Array:
	if kind==FOOT_BATH:
		return [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE,Vector2i(0,2),Vector2i(1,2)] if vertical else [Vector2i.ZERO,Vector2i.RIGHT,Vector2i(2,0),Vector2i.DOWN,Vector2i.ONE,Vector2i(2,1)]
	if kind in TWO_CELL_STATIONS:return [Vector2i.ZERO,Vector2i.DOWN if vertical else Vector2i.RIGHT]
	return SQUARE_CELLS

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
