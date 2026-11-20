extends RefCounted
## Indoor 鶯歌合作陶坊. The room lives in the Yingge region at x 52..67, far east of the outdoor
## tea-stop land (x 8..37), so it never overlaps outdoor terrain; entering only moves the player.
## No data of its own: the indoor clay / potter / kiln stations are aliases of the outdoor ones and
## share the same tea_ceramics record, stock, queue and cooldown (World maps the indoor cell to the
## legacy outdoor cell immediately before TeaCeramics.apply).
##
## The renderer draws one sprite at each leftmost furniture anchor. Stations, work tables and
## north-wall shelves span two cells. PART_CELLS contains the matching second cells for collision.

const TeaCeramics=preload("res://scripts/tea_ceramics.gd")

const REGION:="yingge"
const ROOM:=Rect2i(52,16,16,12)
const DOOR:=Vector2i(20,22)
const EXIT:=Vector2i(59,27)
const PORTAL:="yingge_pottery_portal"
const REACH:=1.6
const STATION_REACH:=3.2
const STATIONS:={Vector2i(56,19):"clay",Vector2i(59,19):"potter",Vector2i(63,19):"kiln"}
## Indoor station -> the legacy outdoor cell that owns the same work point.
const LEGACY_CELLS:={"clay":TeaCeramics.CLAY,"potter":TeaCeramics.POTTER,"kiln":TeaCeramics.KILN}
## tea_ceramics action -> the single indoor station allowed to run it. Everything else is never aliased.
const ACTION_STATIONS:={
	"tea_clay":"clay",
	"tea_potter":"potter","tea_potter_story":"potter",
	"tea_fire":"kiln","tea_fire_take":"kiln","tea_repair":"kiln","tea_fire_pot":"kiln",
}

## Anchor cell -> WorldView object_sprite kind. Every anchor and every PART_CELLS cell blocks movement.
const FURNITURE:={
	# North wall (row 17): lamps and drying benches. Row 18 stays an open walkway behind the stations.
	Vector2i(53,17):"lamp",
	Vector2i(55,17):"long_bench",
	Vector2i(60,17):"long_bench",
	Vector2i(64,17):"long_bench",
	Vector2i(66,17):"lamp",
	# Stations (row 19), all open to the south (row 20-21 is a two-tile front aisle).
	Vector2i(56,19):"chest",
	Vector2i(59,19):"table",
	Vector2i(63,19):"stove",
	# Side planters.
	Vector2i(53,20):"planter",
	Vector2i(66,20):"planter",
	Vector2i(53,25):"planter",
	Vector2i(66,25):"planter",
	# West and east work tables with two stools each; the centre (x 56..63) stays open floor.
	Vector2i(54,22):"table",
	Vector2i(54,23):"chair",
	Vector2i(55,23):"chair",
	Vector2i(64,22):"table",
	Vector2i(64,23):"chair",
	Vector2i(65,23):"chair",
	# Entrance lamps; EXIT's inner cell (59,26) and its neighbours stay open.
	Vector2i(56,26):"lamp",
	Vector2i(62,26):"lamp",
}
## Second cells of 2x1 furniture (anchor + (1,0)). All block movement.
const PART_CELLS:=[
	Vector2i(56,17),Vector2i(61,17),Vector2i(65,17),
	Vector2i(57,19),Vector2i(60,19),Vector2i(64,19),
	Vector2i(55,22),Vector2i(65,22),
]

static func _cell(person:Dictionary)->Vector2i:
	return Vector2i(floori(float(person.get("x",-1000.0))),floori(float(person.get("y",-1000.0))))

## Public players may omit "region"; a present region must be yingge.
static func inside(person:Dictionary)->bool:
	if person.is_empty() or (person.has("region") and str(person.region)!=REGION):return false
	return ROOM.has_point(_cell(person))

static func blocked(cell:Vector2i)->bool:
	if not ROOM.has_point(cell) or cell==EXIT:return false
	if cell.x in [ROOM.position.x,ROOM.end.x-1] or cell.y in [ROOM.position.y,ROOM.end.y-1]:return true
	return FURNITURE.has(cell) or cell in PART_CELLS

static func center(cell:Vector2i)->Vector2:
	return Vector2(cell)+Vector2(0.5,0.5)

## Indoor station cell for a site name ("clay"/"potter"/"kiln"), or Vector2i(-1,-1) when not present.
static func station_cell(site:String)->Vector2i:
	for cell:Vector2i in STATIONS:
		if STATIONS[cell]==site:return cell
	return Vector2i(-1,-1)

## Portal (door outside, exit inside) plus, when inside, "tea:"+site for every station centre.
static func points(person:Dictionary,points_out:Dictionary)->void:
	if person.has("region") and str(person.region)!=REGION:return
	if inside(person):
		points_out[PORTAL]=center(EXIT)
		for cell:Vector2i in STATIONS:points_out["tea:"+STATIONS[cell]]=center(cell)
	else:
		points_out[PORTAL]=center(DOOR)

## Server-side validation of an indoor tea_ceramics request. Returns {"ok":true,"p":legacy_cell} or
## {"ok":false,"message":...}. The player must be inside, the requested cell must be the station that
## owns the action, and the player must be within reach of that station.
static func resolve(person:Dictionary,action:String,p:Vector2i)->Dictionary:
	if not ACTION_STATIONS.has(action) or not inside(person):return {"ok":false,"message":"請走進鶯歌合作陶坊的工作台。"}
	if not STATIONS.has(p) or STATIONS[p]!=ACTION_STATIONS[action]:return {"ok":false,"message":"請到陶坊裡對應的工作台。"}
	var at:=Vector2(float(person.get("x",-1000.0)),float(person.get("y",-1000.0)))
	if not at.is_finite() or at.distance_to(center(p))>STATION_REACH:return {"ok":false,"message":"再靠近一點，才能使用這個工作台。"}
	return {"ok":true,"p":LEGACY_CELLS[STATIONS[p]]}
