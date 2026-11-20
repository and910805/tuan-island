extends RefCounted
## Public indoor Maokong tea house. The room lives in the Maokong region at coordinates far east of the
## outdoor tea-stop land (x 8..37), so it never overlaps outdoor terrain; entering only moves the player.
## Seats are transient: SEAT_KEY is stripped on save, rejoin, exit, movement and disconnect.

const TeaRevisit=preload("res://scripts/tea_revisit.gd")

const REGION:="maokong"
const ROOM:=Rect2i(56,17,15,11)
const DOOR:=Vector2i(19,22)
const EXIT:=Vector2i(63,27)
const PORTAL:="maokong_tea_house_portal"
const SIT:="maokong_tea_house_sit"
const SEAT_KEY:="maokong_tea_house_seat"
const PORTAL_REACH:=1.6
const SEAT_REACH:=2.2
const SEAT_STAY:=0.9

## Anchor cell -> kind. Every cell here blocks movement. Kinds: tea_table, chair, tea_shelf, tea_counter, lamp, planter.
const FURNITURE:={
	# Tea shelves along the north wall, counter in front of the back wall (barista nook behind it).
	Vector2i(58,18):"tea_shelf",
	Vector2i(67,18):"tea_shelf",
	Vector2i(62,19):"tea_counter",
	Vector2i(57,18):"lamp",
	Vector2i(69,18):"lamp",
	Vector2i(57,20):"planter",
	Vector2i(69,20):"planter",
	Vector2i(61,26):"planter",
	Vector2i(65,26):"planter",
	# Table A (west lounge) with two chairs.
	Vector2i(59,22):"tea_table",
	Vector2i(59,21):"chair",
	Vector2i(60,23):"chair",
	# Table B (east lounge) with two chairs.
	Vector2i(66,22):"tea_table",
	Vector2i(66,21):"chair",
	Vector2i(67,23):"chair",
	# Table C (south-west) and Table D (south-east): single-cell tables with chairs on either side.
	Vector2i(58,25):"tea_table",
	Vector2i(57,25):"chair",
	Vector2i(59,25):"chair",
	Vector2i(68,25):"tea_table",
	Vector2i(67,25):"chair",
	Vector2i(69,25):"chair",
}
## Second (and third) cells of multi-tile furniture; the anchor lives in FURNITURE. All block movement.
const PART_CELLS:=[
	Vector2i(59,18),Vector2i(68,18),
	Vector2i(63,19),Vector2i(64,19),
	Vector2i(60,22),Vector2i(67,22),
]
## Chair cell -> open floor tile the sitter occupies (always reachable from the aisles).
const SEAT_FEET:={
	Vector2i(59,21):Vector2i(58,21),
	Vector2i(60,23):Vector2i(61,23),
	Vector2i(66,21):Vector2i(65,21),
	Vector2i(67,23):Vector2i(68,23),
	Vector2i(57,25):Vector2i(57,24),
	Vector2i(59,25):Vector2i(59,24),
	Vector2i(67,25):Vector2i(67,24),
	Vector2i(69,25):Vector2i(69,24),
}
## Walkable decoration (central tea rug); never blocks.
const FLOOR_DECOR:={
	Vector2i(62,21):"tea_rug",Vector2i(63,21):"tea_rug",Vector2i(64,21):"tea_rug",
	Vector2i(62,22):"tea_rug",Vector2i(63,22):"tea_rug",Vector2i(64,22):"tea_rug",
	Vector2i(62,23):"tea_rug",Vector2i(63,23):"tea_rug",Vector2i(64,23):"tea_rug",
	Vector2i(62,24):"tea_rug",Vector2i(63,24):"tea_rug",Vector2i(64,24):"tea_rug",
}

static func _cell(person:Dictionary)->Vector2i:
	return Vector2i(floori(float(person.get("x",-1000.0))),floori(float(person.get("y",-1000.0))))

## Public players may omit "region"; a present region must be maokong.
static func inside(person:Dictionary)->bool:
	if person.is_empty() or (person.has("region") and str(person.region)!=REGION):return false
	return ROOM.has_point(_cell(person))

static func blocked(cell:Vector2i)->bool:
	if not ROOM.has_point(cell) or cell==EXIT:return false
	if cell.x in [ROOM.position.x,ROOM.end.x-1] or cell.y in [ROOM.position.y,ROOM.end.y-1]:return true
	return FURNITURE.has(cell) or cell in PART_CELLS

static func seat_key(chair:Vector2i)->String:
	return "%s:%d,%d"%[SIT,chair.x,chair.y]

## Canonical chair cell for a seat key, or Vector2i(-1,-1) when the key is not a real seat.
static func seat_cell(key:String)->Vector2i:
	var invalid:=Vector2i(-1,-1)
	if not key.begins_with(SIT+":"):return invalid
	var parts:=key.substr(SIT.length()+1).split(",")
	if parts.size()!=2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():return invalid
	var chair:=Vector2i(int(parts[0]),int(parts[1]))
	return chair if SEAT_FEET.has(chair) and seat_key(chair)==key else invalid

static func feet_position(chair:Vector2i)->Vector2:
	return Vector2(SEAT_FEET[chair])+Vector2(0.5,0.5)

## True when somebody other than `ignore` is really sitting at the key. A saved or stale pose
## (wrong region, outside the room, or no longer on the seat tile) never counts.
static func occupied(players:Dictionary,key:String,ignore:="")->bool:
	var chair:=seat_cell(key)
	if chair==Vector2i(-1,-1):return false
	var spot:=feet_position(chair)
	for id in players:
		if str(id)==ignore:continue
		var person:Variant=players[id]
		if not person is Dictionary or str(person.get(SEAT_KEY,""))!=key or not inside(person):continue
		if Vector2(float(person.get("x",-1000.0)),float(person.get("y",-1000.0))).distance_to(spot)<=SEAT_STAY:return true
	return false

static func points(snapshot:Dictionary,person:Dictionary,points_out:Dictionary)->void:
	if str(snapshot.get("region_id",REGION))!=REGION:return
	if inside(person):
		points_out[PORTAL]=Vector2(EXIT)+Vector2(0.5,0.5)
		for chair:Vector2i in SEAT_FEET:
			points_out["%s:%d,%d"%[SIT,chair.x,chair.y]]=Vector2(chair)+Vector2(0.5,0.5)
	elif TeaRevisit.house_open(snapshot):
		points_out[PORTAL]=Vector2(DOOR)+Vector2(0.5,0.5)
