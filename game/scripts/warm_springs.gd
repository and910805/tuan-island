extends RefCounted

const REGION:="jiaoxi"
const LAND:=Rect2i(10,13,31,23)
const POOLS:={
	"spring":{"water":Rect2i(18,18,5,4),"label":"暖泉溪・白天","fish":"glass_shrimp"},
	"upland":{"water":Rect2i(30,25,5,4),"label":"高地冷泉・冬季","fish":"snow_trout"},
}
const TERRAIN=preload("res://assets/village-preview/terrain.png")

static func spot(cell:Vector2i)->String:
	for id in POOLS:
		if POOLS[id].water.has_point(cell):return id
	return ""

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
