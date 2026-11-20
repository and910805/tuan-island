extends RefCounted
const Transit=preload("res://scripts/transit.gd")
const HOME := "home"
const LANYANG := "lanyang"
const JINGUASHI := "jinguashi"
const TIANWEI := "tianwei"
const BEIMEN := "beimen"
const FlowerNursery = preload("res://scripts/flower_nursery.gd")
const SaltPan = preload("res://scripts/salt_pan.gd")
const Springs = preload("res://scripts/warm_springs.gd")
const Bamboo = preload("res://scripts/bamboo_grove.gd")
const StarGarden = preload("res://scripts/star_garden.gd")
const Mines = preload("res://scripts/mine_depths.gd")
const Cart = preload("res://scripts/party_cart.gd")
const TeaHouse = preload("res://scripts/tea_house_interior.gd")
const Pottery = preload("res://scripts/pottery_workshop_interior.gd")
const MineLayout = preload("res://scripts/mine_layout.gd")
const ALL := [HOME,LANYANG,JINGUASHI,"toucheng","ruifang","jiufen","mine_1","mine_2","mine_3","mine_4","mine_5","maokong","yingge",TIANWEI,BEIMEN,Springs.REGION,Bamboo.REGION,StarGarden.REGION,"mine_6","mine_7","mine_8","mine_9","mine_10","mine_11","mine_12","mine_13","mine_14","mine_15",Cart.REGION]
## T067 deep floors carry no pre-existing tile edits; older saves load empty layers.
const DEEP_MINES := ["mine_6","mine_7","mine_8","mine_9","mine_10","mine_11","mine_12","mine_13","mine_14","mine_15"]
const ANGLING_RESERVES := [Springs.REGION,Bamboo.REGION,StarGarden.REGION]
const SIZE := Vector2i(80,60)
const RICE_BANKS := [Rect2i(32,24,1,4),Rect2i(35,24,1,4)]

static func rice_paddy(p:Vector2i,region:String)->bool:
	return region==LANYANG and (RICE_BANKS[0].has_point(p) or RICE_BANKS[1].has_point(p))
const LAYERS := ["crops","objects","ground","roofs","edges","forest","removed","damage","next_network_check","next_logistics_check"]

static func fresh() -> Dictionary:
	var result := {}
	for field in LAYERS:
		result[field] = 0.0 if field.begins_with("next_") else {}
	return result

static func exit_cell(region: String) -> Vector2i:
	if region==Cart.REGION:return Cart.EXIT
	if Transit.STATIONS.has(region):return Transit.STATIONS[region].cell
	return Vector2i(11,20) if region != HOME else Vector2i(47,30)

static func spawn(region: String) -> Vector2:
	if region==Cart.REGION:return Cart.SPAWN
	if Transit.STATIONS.has(region):return Transit.STATIONS[region].arrival
	return Vector2(12.5,20.5) if region != HOME else Vector2(46.5,30.5)

static func label(region: String) -> String:
	if region==Cart.REGION:return "金瓜石・礦車搬運坑道"
	if Transit.STATIONS.has(region):return Transit.STATIONS[region].name
	if region in Mines.IDS:return "合作礦場第 %d 層" % (Mines.IDS.find(region)+1)
	match region:
		LANYANG:return "蘭陽試作田"
		JINGUASHI:return "金瓜石山城"
	return "風鈴渡口"

static func arrival_notice(region:String)->String:
	return "已抵達%s。"%label(region)

static func land(p: Vector2i, region: String = LANYANG) -> bool:
	if region==Cart.REGION:return Cart.BOUNDS.has_point(p)
	if region==StarGarden.REGION:return StarGarden.LAND.has_point(p) and not StarGarden.POOL.has_point(p)
	if region==Bamboo.REGION:return Bamboo.LAND.has_point(p) and not Bamboo.water(p)
	if region==Springs.REGION:return Springs.INN_ROOM.has_point(p) or (Springs.LAND.has_point(p) and Springs.spot(p).is_empty())
	if region == TIANWEI:return FlowerNursery.land(p)
	if region == BEIMEN:return SaltPan.land(p)
	if region==TeaHouse.REGION and TeaHouse.ROOM.has_point(p):return true
	if region==Pottery.REGION and Pottery.ROOM.has_point(p):return true
	if region in Transit.TEA_STOPS:
		return Rect2i(8,12,30,19).has_point(p) and not (p.x>33 and p.y<16) and not (p.x<11 and p.y>27)
	if region in Transit.LOCAL:return Transit.PLAZA.has_point(p)
	var depth:=Mines.IDS.find(region)+1
	if depth>0:return MineLayout.land(p,depth)
	if region == JINGUASHI:
		if preload("res://scripts/bobo_workshop.gd").ANNEX.has_point(p):return true
		return p.x >= 6 and p.x <= 53 and p.y >= 9 + int(maxi(p.x-34,0)/3.0) and p.y <= 43 - int(maxi(p.x-30,0)/4.0)
	return p.x >= 5 and p.x <= 72 and p.y >= 6 and p.y <= 52

static func water(p: Vector2i, region: String = LANYANG) -> bool:
	if region==Cart.REGION:return not land(p,region)
	if region in ANGLING_RESERVES:return not land(p,region)
	if region == TIANWEI:return false
	if region == BEIMEN:return SaltPan.water(p)
	if region in Transit.TEA_STOPS:return false
	if region in Transit.LOCAL:return false
	if region in Mines.IDS:return not land(p,region) or (region == "mine_3" and Mines.POOL.has_point(p))
	if region == JINGUASHI:return not land(p,region)
	return not land(p,region) or (p.x in [33,34] and p.y not in [28,29,30])

const TRANSIT_WALKWAYS := {
	# Leave the west-bank rice plots and the irrigation/forestry work sites free.
	LANYANG:{
		"strips":[Rect2i(12,20,11,1),Rect2i(22,21,1,8),Rect2i(23,28,10,1),Rect2i(32,29,1,1)],
		"destination":Vector2i(32,29),
	},
	JINGUASHI:{"strips":[Rect2i(12,20,11,1),Rect2i(22,21,6,1),Rect2i(27,20,1,1)],"destination":Vector2i(27,20)},
}

static func transit_walkway(p:Vector2i,region:String)->bool:
	if not TRANSIT_WALKWAYS.has(region):return false
	for strip:Rect2i in TRANSIT_WALKWAYS[region].strips:
		if strip.has_point(p):return true
	return false

static func protected(p: Vector2i, region: String = LANYANG) -> bool:
	if region==Cart.REGION:return true
	if region==Springs.REGION:return not Springs.BENCH_CLEARING.has_point(p)
	if region==Bamboo.REGION:return not Bamboo.TEA_BEDS.has_point(p)
	if region in ANGLING_RESERVES:return true
	if region == TIANWEI:return FlowerNursery.protected(p)
	if region == BEIMEN:return SaltPan.protected(p)
	if region in Transit.TEA_STOPS:return true
	if region in Transit.LOCAL:return true
	if region in Mines.IDS:return p in [Mines.UP,Mines.DOWN,Mines.REST,Mines.SERVICE,Vector2i(12,20)] or p in Mines.NODES or (p==Mines.LIFT and Mines.depth_of(region)>Mines.SHALLOW_DEPTH)
	if region == JINGUASHI:
		const Mine = preload("res://scripts/jinguashi.gd")
		if preload("res://scripts/bobo_workshop.gd").ANNEX.has_point(p):return true
		return (p.y == 20 and p.x in [11,12]) or p in Mine.NODES or Mine.ENTRANCE_FOOTPRINT.has_point(p) or p == Mines.ENTRY
	return p.x in [33,34] or (p.y == 20 and p.x in [11,12])

static func resource(p: Vector2i, region: String = LANYANG) -> String:
	if region==Cart.REGION:return ""
	if rice_paddy(p,region):return ""
	if region in ANGLING_RESERVES:return ""
	if region == TIANWEI or region == BEIMEN:return ""
	if region in Transit.TEA_STOPS:return ""
	if region in Mines.IDS:return ""
	if region == JINGUASHI and p.x <= 36 and p.y >= 17 and p.y <= 25:
		return ""
	if water(p,region) or protected(p,region) or (p.x < 27 and p.y >= 14 and p.y <= 33):
		return ""
	var pattern := absi(p.x * 7127 + p.y * 19391 + p.x * p.y * 193)
	if pattern % 17 == 0:return "tree"
	if pattern % 23 == 0:return "rock"
	if pattern % 31 == 0:return "grass"
	return ""

static func tea_blocked(p:Vector2i,region:String)->bool:
	if region not in Transit.TEA_STOPS:return false
	# The workshop door is always an open walkable tile (never a station, rect obstacle or water).
	if region==Pottery.REGION and p==Pottery.DOOR:return false
	if not land(p,region):return true
	if Rect2i(18,17,4,1).has_point(p):return true
	if region=="yingge" and Rect2i(23,17,4,1).has_point(p):return true
	return p==Vector2i(23,20) or (region=="maokong" and p==Vector2i(26,20))

# 田尾花圃的碰撞：花圃範圍外、棚屋、站點與公共花園都不能走入；其他區域一律 false。
static func flower_blocked(p:Vector2i,region:String)->bool:
	if region != TIANWEI:return false
	return not land(p,region) or FlowerNursery.blocked(p)

# 北門鹽田的碰撞：海、閘門水道、鹽田、站牌與道具都不能走入；其他區域一律 false。
static func salt_blocked(p:Vector2i,region:String)->bool:
	if region != BEIMEN:return false
	return not land(p,region) or SaltPan.blocked(p)
