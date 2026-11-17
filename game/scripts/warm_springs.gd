extends RefCounted

const REGION:="jiaoxi"
const WARMTH_FIELD:="ginger_warm_until"
const WARMTH_SECONDS:=480.0
const Weather=preload("res://scripts/weather.gd")
const LAND:=Rect2i(10,13,31,23)
const BENCH_CLEARING:=Rect2i(27,26,2,2)
const REST_SEAT_KEY:="nuannuan_rest_seat"
const REST_REPLAY:="nuannuan_rest_replay"
const REST_SEATS:={"stream":Vector2i(18,22),"porch":Vector2i(29,22),"pool":Vector2i(23,22)}
const INN_FOOTPRINT:=Rect2i(27,19,4,3)
const INN_DOOR:=Vector2i(28,22)
const INN_POINT:="warm_springs_inn"
const INN_ART=preload("res://assets/ui-life/warm-springs-inn.png")
const INN_PORTAL:="warm_springs_inn_portal"
const INN_USE:="warm_springs_inn_use"
const INN_CHAIR_FEET:={Vector2i(67,24):Vector2i(67,25),Vector2i(66,25):Vector2i(65,25)}
const INN_ROOM:=Rect2i(60,20,11,8)
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
}
const BATH_KEY:="jiaoxi_public_bath_repaired"
const BATH_ACTION:="jiaoxi_public_bath"
const BATH_ORIGIN:=Vector2i(24,18)
const BATH_FOOTPRINT:=Rect2i(BATH_ORIGIN,Vector2i(3,2))
const BATH_ENTRANCE:=Vector2i(25,20)
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

static func draw_inn(canvas:CanvasItem,at:Vector2,time:float,reduced_motion:bool)->void:
	canvas.draw_texture(INN_ART,at-Vector2(0,32))
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
	return INN_FURNITURE.has(cell) or cell in [Vector2i(61,23),Vector2i(68,23),Vector2i(64,24)]

static func room_interactions(points:Dictionary)->void:
	points[INN_PORTAL]=Vector2(INN_EXIT)+Vector2(0.5,0.5)
	for cell:Vector2i in INN_FURNITURE:
		var kind:String=INN_FURNITURE[cell]
		if kind=="chair" or kind=="inn_quilt_bed":
			var anchor:=Vector2(cell)+Vector2(0.5,0.5 if kind=="chair" else 1.5)
			points["%s:%d,%d"%[INN_USE,cell.x,cell.y]]=anchor

static func warmth_left(person:Dictionary,time:float)->float:
	return maxf(0.0,float(person.get(WARMTH_FIELD,0.0))-time)

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
