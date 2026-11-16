extends RefCounted

const TERRAIN=preload("res://assets/village-preview/terrain.png")
const FURNITURE=preload("res://scripts/furniture_sprite_art.gd")
const Regions=preload("res://scripts/regions.gd")

static func draw_ground(canvas:CanvasItem,at:Vector2,p:Vector2i,wet:bool) -> void:
	var index:=0
	if wet:
		index=9 if p.x in [33,34] else 8
	elif Regions.rice_paddy(p,Regions.LANYANG):
		index=15
	elif p.x in [33,34]:
		index=10
	elif p.y==20 and p.x in range(11,25) or p.y in [28,30] and p.x in range(17,38) or p.x in [17,25] and p.y in range(20,31):
		index=4
	elif p.x in range(18,25) and p.y in range(22,28):
		index=5
	else:
		index=0 if sin(p.x*0.63)+cos(p.y*0.47)>0.3 else 1
	var region:=Rect2((index%4)*32,(index/4)*32,32,32)
	canvas.draw_texture_rect_region(TERRAIN,Rect2(at,Vector2(32,32)),region)

static func draw_exit(canvas:CanvasItem,at:Vector2) -> void:
	FURNITURE.draw_sprite(canvas,at,"sign")
