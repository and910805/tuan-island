extends RefCounted

const REGION:="star_garden"
const LAND:=Rect2i(11,16,26,18)
const POOL:=Rect2i(23,19,6,5)
const POOLS:={"reflection":{"water":POOL,"label":"映星池・夜間","fish":"star_spot"}}
const TERRAIN=preload("res://assets/village-preview/terrain.png")

static func ground(canvas:CanvasItem,at:Vector2,cell:Vector2i)->void:
	var frame:=posmod(cell.x*3+cell.y*7,3)%2
	var tint:=Color("b6afc8")
	if not LAND.has_point(cell) or POOL.has_point(cell):
		frame=9 if POOL.has_point(cell) else 8
		tint=Color("a3accf")
	elif cell.y in [25,26]:
		frame=4
		tint=Color("e6d0bb")
	canvas.draw_texture_rect_region(TERRAIN,Rect2(at,Vector2(32,32)),Rect2((frame%4)*32,(frame/4)*32,32,32),tint)
