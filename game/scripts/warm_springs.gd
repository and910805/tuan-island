extends RefCounted

const REGION:="jiaoxi"
const WARMTH_FIELD:="ginger_warm_until"
const WARMTH_SECONDS:=480.0
const Weather=preload("res://scripts/weather.gd")
const MealBuff=preload("res://scripts/meal_buff.gd")
const LAND:=Rect2i(10,13,31,23)
const BENCH_CLEARING:=Rect2i(27,26,2,2)
const REST_SEAT_KEY:="nuannuan_rest_seat"
const REST_REPLAY:="nuannuan_rest_replay"
const REST_SEATS:={"stream":Vector2i(18,22),"porch":Vector2i(29,22),"pool":Vector2i(23,22)}
const REST_JOIN:="nuannuan_rest_join"
const REST_PHOTO_POINT:="nuannuan_rest_photo"
const REST_FRIEND_PREFIX:="friend:"
const REST_FRIEND_OFFSET:=Vector2(1.42,0.66)
const REST_PRIMARY_OFFSET:=Vector2(0.55,0.66)
const REST_REACH:=1.6
const INN_FOOTPRINT:=Rect2i(27,19,4,3)
const INN_DOOR:=Vector2i(28,22)
const INN_POINT:="warm_springs_inn"
const INN_ART=preload("res://assets/ui-life/warm-springs-inn.png")
const ENTRANCE_LEAVES=preload("res://assets/ui-life/leaf-floor-mat.png")
const Items=preload("res://scripts/inventory_item_art.gd")
enum Entrance { LEAVES, SWEPT, LIT }
const INN_PORTAL:="warm_springs_inn_portal"
const INN_USE:="warm_springs_inn_use"
const INN_CHAIR_FEET:={
	Vector2i(67,24):Vector2i(67,25),Vector2i(66,25):Vector2i(65,25),
	Vector2i(71,22):Vector2i(71,23),Vector2i(72,23):Vector2i(72,24),
}
const INN_ROOM:=Rect2i(60,17,15,11)
# Second cells of two-cell furniture (the anchor lives in INN_FURNITURE); all block movement.
const INN_PART_CELLS:=[Vector2i(61,23),Vector2i(68,23),Vector2i(64,24),Vector2i(65,19),Vector2i(62,19)]
const INN_RUG_ANCHOR:=Vector2i(71,22)
const INN_EXIT:=Vector2i(65,27)
const INN_FURNITURE:={
	Vector2i(61,22):"inn_quilt_bed",
	Vector2i(62,22):"lamp",
	Vector2i(68,22):"inn_quilt_bed",
	Vector2i(69,22):"inn_lattice_wardrobe",
	Vector2i(63,24):"inn_fabric_screen",
	Vector2i(66,24):"inn_tea_table",
	Vector2i(67,24):"chair",
	Vector2i(66,25):"chair",
	# Reception: whitewood register counter (64-65,19), welcome sign, lamp.
	Vector2i(64,19):"whitewood_register",
	Vector2i(66,19):"inn_welcome_sign",
	Vector2i(63,19):"lamp",
	Vector2i(61,19):"inn_luggage_rack",
	# Guest lounge on the east rug: tea table, two chairs, lamp.
	Vector2i(72,22):"inn_tea_table",
	Vector2i(71,22):"chair",
	Vector2i(72,23):"chair",
	Vector2i(73,22):"lamp",
	Vector2i(73,19):"planter",
	Vector2i(73,25):"planter",
}
const BATH_KEY:="jiaoxi_public_bath_repaired"
const BATH_ACTION:="jiaoxi_public_bath"
const BATH_ORIGIN:=Vector2i(24,18)
const BATH_FOOTPRINT:=Rect2i(BATH_ORIGIN,Vector2i(3,2))
const BATH_ENTRANCE:=Vector2i(25,20)
const CRACK_ACTION:="nuannuan_mark_bath_crack"
const CRACK_KEY:="nuannuan_bath_cracks"
const CRACK_REACH:=1.25
const CRACK_SITES:=[Vector2i(23,18),Vector2i(27,18),Vector2i(24,21)]
const CRACK_MARK_OFFSETS:=[Vector2(26,11),Vector2(-26,13),Vector2(23,-57)]
const CRACK_NAMES:=["靠溪的裂縫","池角的裂縫","台階旁的裂縫"]
const CRACK_MASK:=0b111
const BATH_SEATS:=[Vector2(0.43,2.32),Vector2(1.14,2.32),Vector2(1.86,2.32),Vector2(2.57,2.32)]
const POOLS:={
	"spring":{"water":Rect2i(18,18,5,4),"label":"暖泉溪・白天","fish":"glass_shrimp"},
	"upland":{"water":Rect2i(30,25,5,4),"label":"高地冷泉・冬季","fish":"snow_trout"},
}
const TERRAIN=preload("res://assets/village-preview/terrain.png")

static func spot(cell:Vector2i)->String:
	for id in POOLS:
		if POOLS[id].water.has_point(cell):return id
	return ""

static func crack_survey_open(snapshot:Dictionary)->bool:
	return snapshot.get("resident_goals",{}).get("nuannuan",{}).get("2",{}).get("state")=="open"

static func crack_marked(mask:int,index:int)->bool:
	return (mask & (1<<index))!=0

static func crack_interactions(snapshot:Dictionary,points:Dictionary,position:Vector2)->void:
	if not crack_survey_open(snapshot):return
	var mask:=int(snapshot.get("own_inn_cracks",0))
	for index in CRACK_SITES.size():
		var center:=Vector2(CRACK_SITES[index])+Vector2(0.5,0.5)
		if not crack_marked(mask,index) and position.distance_to(center)<=CRACK_REACH:
			points["%s:%d"%[CRACK_ACTION,index]]=center

## Valid seat choice for either a primary key ("stream") or a second-seat key ("friend:stream"); "" otherwise.
static func rest_choice(key:String)->String:
	var choice:=key.trim_prefix(REST_FRIEND_PREFIX)
	return choice if REST_SEATS.has(choice) else ""

## Standing spot for a seat key: primary beside the seat, second seat on its open side.
static func rest_spot(key:String)->Vector2:
	var choice:=rest_choice(key)
	if choice.is_empty():return Vector2(-1000,-1000)
	var offset:=REST_FRIEND_OFFSET if key.begins_with(REST_FRIEND_PREFIX) else REST_PRIMARY_OFFSET
	return Vector2(REST_SEATS[choice])+offset

## Public players may omit "region"; a present region must be jiaoxi.
static func rest_occupied(players:Dictionary,seat_key:String)->bool:
	if rest_choice(seat_key).is_empty() or seat_key.is_empty():return false
	for id in players:
		var person:Variant=players[id]
		if not person is Dictionary:continue
		if person.has("region") and str(person.region)!=REGION:continue
		if str(person.get(REST_SEAT_KEY,""))==seat_key:return true
	return false

static func rest_interactions(snapshot:Dictionary,points:Dictionary,position:Vector2,own_id:String)->void:
	if snapshot.get("region_id",REGION)!=REGION:return
	var players:Dictionary=snapshot.get("players",{})
	var own:Dictionary=players.get(own_id,{})
	if not rest_choice(str(own.get(REST_SEAT_KEY,""))).is_empty():
		points[REST_PHOTO_POINT]=position
		return
	for choice:String in REST_SEATS:
		var anchor:=Vector2(REST_SEATS[choice])+REST_FRIEND_OFFSET
		if position.distance_to(anchor)>REST_REACH:continue
		if rest_occupied(players,choice) and not rest_occupied(players,REST_FRIEND_PREFIX+choice):
			points["%s:%s"%[REST_JOIN,choice]]=anchor

static func entrance_progress(snapshot:Dictionary)->Entrance:
	var story:Dictionary=snapshot.get("resident_goals",{}).get("nuannuan",{}).get("1",{})
	if story.get("state")=="done":return Entrance.LIT
	for need:Dictionary in story.get("needs",[]):
		if need.get("id")=="inn_entrance" and need.get("met",false):return Entrance.SWEPT
	return Entrance.LEAVES

static func draw_inn(canvas:CanvasItem,at:Vector2,time:float,reduced_motion:bool,entrance:=Entrance.LIT,sweep_age:=INF)->void:
	canvas.draw_texture(INN_ART,at-Vector2(0,32))
	for lamp_x in [22,107]:
		if entrance!=Entrance.LIT:
			var lamp:=Rect2(lamp_x-5,68,11,11)
			canvas.draw_texture_rect_region(INN_ART,Rect2(at-Vector2(0,32)+lamp.position,lamp.size),lamp,Color("716679"))
		else:
			var heat:=0.10 if reduced_motion else 0.11+sin(time*3.1+lamp_x)*0.035
			canvas.draw_circle(at+Vector2(lamp_x,42),10,Color(1.0,0.69,0.23,heat))
	var sweeping:=not reduced_motion and entrance==Entrance.SWEPT and sweep_age<0.56
	if entrance==Entrance.LEAVES or sweeping:
		var progress:=clampf(sweep_age/0.56,0.0,1.0) if sweeping else 0.0
		var leaves:=Color("d5aa75")
		leaves.a=1.0-progress
		for pile:Rect2 in [Rect2(39,96,17,14),Rect2(59,97,13,11),Rect2(84,93,16,13)]:
			var side:=-1.0 if pile.position.x<64 else 1.0
			var drift:=Vector2(side*progress*20.0,-sin(progress*PI)*7.0).round()
			canvas.draw_texture_rect(ENTRANCE_LEAVES,Rect2(at+pile.position+drift,pile.size),false,leaves)
	if entrance==Entrance.LEAVES:
		var pebble:=Items.icon("stone")
		canvas.draw_texture_rect(pebble,Rect2(at+Vector2(72,98),Vector2(11,11)),false)
	if reduced_motion:return
	for i in 3:
		var phase:=fposmod(time*0.34+i*0.29,1.0)
		var position:=at+Vector2(96+phase*9.0,-14-phase*24.0)
		canvas.draw_circle(position,2.8+phase*5.0,Color(0.9,0.96,0.88,sin(phase*PI)*0.26))

static func in_inn(person:Dictionary)->bool:
	return not person.is_empty() and INN_ROOM.has_point(Vector2i(floori(float(person.x)),floori(float(person.y))))

static func room_blocked(cell:Vector2i)->bool:
	if not INN_ROOM.has_point(cell):return false
	if cell==INN_EXIT:return false
	if cell.x in [INN_ROOM.position.x,INN_ROOM.end.x-1] or cell.y in [INN_ROOM.position.y,INN_ROOM.end.y-1]:return true
	return INN_FURNITURE.has(cell) or cell in INN_PART_CELLS

static func room_interactions(points:Dictionary)->void:
	points[INN_PORTAL]=Vector2(INN_EXIT)+Vector2(0.5,0.5)
	for cell:Vector2i in INN_FURNITURE:
		var kind:String=INN_FURNITURE[cell]
		if kind=="chair" or kind=="inn_quilt_bed":
			var anchor:=Vector2(cell)+Vector2(0.5,0.5 if kind=="chair" else 1.5)
			points["%s:%d,%d"%[INN_USE,cell.x,cell.y]]=anchor

static func warmth_left(person:Dictionary,time:float)->float:
	var effect:=MealBuff.read(person,time)
	return float(effect.left) if effect.get("id","")==MealBuff.GINGER else 0.0

static func highland_hint(snapshot:Dictionary,person:Dictionary)->String:
	if snapshot.get("region_id")!=REGION:return ""
	var time:=float(snapshot.get("time",0.0))
	var left:=warmth_left(person,time)
	if left>0.0:
		var seconds:=ceili(left)
		return "暖薑茶保暖 · %d:%02d"%[seconds/60,seconds%60]
	if Weather.season_on_day(Weather.day_index(time))!="winter":return ""
	var cell:=Vector2i(floori(float(person.get("x",0))),floori(float(person.get("y",0))))
	var cold_pool:Rect2i=POOLS.upland.water
	if not cold_pool.grow(3).has_point(cell):return ""
	if snapshot.get("roofs",{}).has("%d,%d"%[cell.x,cell.y]):return ""
	return "冷泉一帶寒涼 · 喝杯暖薑茶暖身"

static func ground(canvas:CanvasItem,at:Vector2,cell:Vector2i)->void:
	var pool:=spot(cell)
	var frame:=posmod(cell.x+cell.y,2)
	var tint:=Color("d4dfa9")
	if not LAND.has_point(cell):
		frame=8
		tint=Color("6c9897")
	elif not pool.is_empty():
		frame=9
		tint=Color("9bdfca") if pool=="spring" else Color("a8cdeb")
	elif cell.y in [23,24] or (cell.x in [13,14] and cell.y in range(23,32)):
		frame=4
		tint=Color.WHITE
	var source:=Rect2((frame%4)*32,(frame/4)*32,32,32)
	canvas.draw_texture_rect_region(TERRAIN,Rect2(at,Vector2(32,32)),source,tint)
