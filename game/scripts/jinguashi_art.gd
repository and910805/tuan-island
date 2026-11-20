extends RefCounted
const TERRAIN=preload("res://assets/village-preview/terrain.png")
const Furniture=preload("res://scripts/furniture_sprite_art.gd")
const STATION:=Vector2i(5,19)
const ENTRANCE_ANCHOR:=Vector2i(28,18)
static var entrance:Texture2D

static func draw_entrance(canvas:CanvasItem,at:Vector2) -> void:
	if entrance==null:
		var image:=load("res://assets/jinguashi/mine-entrance-open.png").get_image() as Image
		image.resize(192,128,Image.INTERPOLATE_NEAREST)
		entrance=ImageTexture.create_from_image(image)
	canvas.draw_texture_rect(entrance,Rect2(at+Vector2(-128,-160),Vector2(288,192)),false)

static func draw_ground(canvas:CanvasItem,at:Vector2,p:Vector2i,land:bool)->void:
	var ridge:=sin(p.x*0.71)+cos(p.y*0.53)+sin((p.x+p.y)*1.29)*0.28
	var lane:=20.0+sin(p.x*0.38)*0.6
	var trail:=p.x>=9 and p.x<=28 and absf(p.y-lane)<1.45
	var working:=Vector2(float(p.x-31)/5.7,float(p.y-22)/3.2).length()<1.0+ridge*0.13
	var index:=8
	var tint:=Color("6f9391")
	if land:
		if trail or working:
			index=4 if ridge<1.0 else 5
			tint=Color("c49d82") if trail else Color("b59e91")
		elif ridge>0.3:
			index=1 if ridge>1.2 else 3
			tint=Color("a7ae89")
		else:
			index=5 if ridge< -1.0 else 4
			tint=Color("a49a92")
	elif p.x in [4,5] and p.y in range(17,22):
		index=5
		tint=Color("a09285")
	var region:=Rect2((index%4)*32,(index/4)*32,32,32)
	canvas.draw_texture_rect_region(TERRAIN,Rect2(at,Vector2(32,32)),region,tint)

static func draw_station_sign(canvas:CanvasItem,at:Vector2)->void:
	Furniture.draw_sprite(canvas,at,"sign")

static func draw_station(canvas:Node2D,at:Vector2,village_art) -> void:
	if village_art!=null:
		canvas.draw_texture_rect_region(TERRAIN,Rect2(at,Vector2(32,32)),Rect2(32,32,32,32),Color("9d8980"))
		village_art.draw_prop(canvas,at,8,0.94)

static func draw_rock_ledge(canvas:Node2D,at:Vector2,village_art,p:Vector2i) -> void:
	if village_art!=null:village_art.draw_prop(canvas,at,6,0.84+0.12*float((p.x+p.y)%3))

static func draw_mine_bed(canvas:CanvasItem,at:Vector2) -> void:
	canvas.draw_texture_rect_region(TERRAIN,Rect2(at,Vector2(32,32)),Rect2(32,32,32,32),Color("a49286"))
