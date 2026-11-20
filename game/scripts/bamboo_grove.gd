extends RefCounted

const REGION:="bamboo_grove"
const LAND:=Rect2i(10,15,27,17)
const TEA_BEDS:=Rect2i(17,21,4,2)
const CLUMPS:Array[Vector2i]=[Vector2i(16,19),Vector2i(19,18),Vector2i(21,19),Vector2i(15,22)]
const ITEM:="bamboo"
const YIELD:=4
const REGROW_SECONDS:=120.0
const CUT_FIELD:="bamboo_cut"
const POOLS:={"brook":{"water":Rect2i(23,17,4,10),"label":"竹澗・晨間微風","fish":"bamboo_ayu"}}
const TERRAIN=preload("res://assets/village-preview/terrain.png")
const BAMBOO_CLUMP=preload("res://assets/life-art/bamboo-clump.png")
const BAMBOO_STUBS=preload("res://assets/life-art/bamboo-stubs.png")

static func water(cell:Vector2i)->bool:
	return POOLS.brook.water.has_point(cell)

static func breezy(minute:float)->bool:
	return minute>=360.0 and minute<660.0

static func clump_key(cell:Vector2i)->String:
	return "%d,%d"%[cell.x,cell.y]

static func ready(state:Dictionary,cell:Vector2i)->bool:
	return float(state.get(CUT_FIELD,{}).get(clump_key(cell),0.0))<=float(state.get("time",0.0))

static func cut(state:Dictionary,cell:Vector2i)->void:
	var times:Dictionary=state.get(CUT_FIELD,{})
	times[clump_key(cell)]=float(state.time)+REGROW_SECONDS
	state[CUT_FIELD]=times

static func valid(state:Dictionary)->bool:
	var times:Variant=state.get(CUT_FIELD,{})
	if not times is Dictionary or times.size()>CLUMPS.size():return false
	var allowed:Dictionary={}
	for cell in CLUMPS:allowed[clump_key(cell)]=true
	for cell in times:
		if not allowed.has(cell):return false
		var time:Variant=times[cell]
		if not (time is float or time is int) or not is_finite(float(time)):return false
		if float(time)<0.0 or float(time)>float(state.time)+REGROW_SECONDS+0.001:return false
	return true

static func ground(canvas:CanvasItem,at:Vector2,cell:Vector2i)->void:
	var frame:=posmod(cell.x*3+cell.y*7,3)%2
	var tint:=Color("b2cd9a")
	if not LAND.has_point(cell) or water(cell):
		frame=9 if water(cell) else 8
		tint=Color("89c9ba")
	elif TEA_BEDS.has_point(cell):
		frame=15
		tint=Color.WHITE
	elif cell.y in [25,26] and cell.x<23:
		frame=4
		tint=Color.WHITE
	canvas.draw_texture_rect_region(TERRAIN,Rect2(at,Vector2(32,32)),Rect2((frame%4)*32,(frame/4)*32,32,32),tint)

static func draw_clump(canvas:CanvasItem,at:Vector2,mature:bool)->void:
	if mature:canvas.draw_texture(BAMBOO_CLUMP,at+Vector2(-4,-26))
	else:canvas.draw_texture(BAMBOO_STUBS,at+Vector2(2,13))
