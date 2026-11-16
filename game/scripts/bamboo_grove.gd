extends RefCounted

const REGION:="bamboo_grove"
const LAND:=Rect2i(10,15,27,17)
const TEA_BEDS:=Rect2i(17,21,4,2)
const POOLS:={"brook":{"water":Rect2i(23,17,4,10),"label":"竹澗・晨間微風","fish":"bamboo_ayu"}}
const TERRAIN=preload("res://assets/village-preview/terrain.png")

static func water(cell:Vector2i)->bool:
	return POOLS.brook.water.has_point(cell)

static func breezy(minute:float)->bool:
	return minute>=360.0 and minute<660.0

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
