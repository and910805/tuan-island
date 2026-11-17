extends RefCounted
const PATH:="res://assets/transit/atlas.png"
const GROUND=preload("res://assets/village-preview/terrain.png")
const Transit=preload("res://scripts/transit.gd")
const CAVERN=preload("res://assets/mine/cavern.png")
const VOYAGE_ART=preload("res://assets/transit/achao-voyage.png")
const NAMES:={"toucheng":"宜蘭・頭城車站","ruifang":"新北・瑞芳轉乘廣場","jiufen":"新北・九份山城"}
const INDICES:={"toucheng":0,"station":0,"ruifang":1,"jiufen":2,"train":3,"bus":4,"lantern":5}
static var atlas:Texture2D
static var icons:Dictionary={}

static func icon(kind:String)->Texture2D:
	if icons.has(kind):return icons[kind]
	if kind in ["ferry","cooperative_boat"]:
		var boat:=AtlasTexture.new()
		boat.atlas=VOYAGE_ART
		boat.region=Rect2(48 if kind=="cooperative_boat" else 0,0,48,48)
		boat.filter_clip=true
		icons[kind]=boat
		return boat
	if not INDICES.has(kind):return null
	if atlas==null and ResourceLoader.exists(PATH):atlas=load(PATH)
	if atlas==null:return null
	var index:int=INDICES[kind]
	var tile:=AtlasTexture.new()
	tile.atlas=atlas
	tile.region=Rect2((index%3)*128,(index/3)*96,128,96)
	tile.filter_clip=true
	icons[kind]=tile
	return tile

static func ground(canvas:CanvasItem,at:Vector2,p:Vector2i,region:String,land:bool)->void:
	var index:=0
	var tint:=Color.WHITE
	if land:
		match region:
			"toucheng":
				var lane:=p.y in range(18,22) or (p.x in range(11,15) and p.y in range(20,27))
				index=4 if lane else 0
				tint=Color("ead2a7") if lane else Color("b8c69e")
			"ruifang":
				var square:=p.y in range(18,27) and p.x in range(11,35)
				index=11 if square else 0
				tint=Color("e0d1bb") if (p.x+p.y)%6==0 else Color("d3c6b4")
			"jiufen":
				var lane:=p.y in range(19,23) or (p.y in range(22,28) and p.x in range(11,17))
				index=11 if lane else 14
				tint=Color("b59783").lightened(float((p.x+p.y)%3)*0.04) if lane else Color("a39686")
	else:
		index=9 if region!="ruifang" else 6
		tint=Color("749995") if region!="ruifang" else Color("655b52")
		if p.y<Transit.PLAZA.position.y and p.x>=Transit.PLAZA.position.x and p.x<Transit.PLAZA.end.x:
			index=6
			tint=Color("817663") if region=="toucheng" else Color("63594c")
	canvas.draw_texture_rect_region(GROUND,Rect2(at,Vector2(32,32)),Rect2((index%4)*32,(index>>2)*32,32,32),tint)
	if land and region=="jiufen" and p.x in range(16,29) and p.y in [19,20,21] and (p.x+p.y)%3!=0:
		canvas.draw_texture_rect_region(GROUND,Rect2(at,Vector2(32,32)),Rect2(96,64,32,32),Color("c1b09b"))
	if Transit.blocked(p,region):
		canvas.draw_texture_rect_region(GROUND,Rect2(at,Vector2(32,32)),Rect2(64,32,32,32),Color("807063"))
	elif region=="toucheng" and p.y==17 and p.x in range(10,20):
		var zoom_value:float=canvas.view_zoom()
		canvas.draw_set_transform((at+Vector2(32,0))*zoom_value,PI/2.0,Vector2.ONE*zoom_value)
		canvas.draw_texture_rect_region(CAVERN,Rect2(4,0,24,32),Rect2(151,17,23,39))
		canvas.draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE*zoom_value)

static func draw_sprite(canvas:CanvasItem,kind:String,dest:Rect2)->void:
	var sprite:=icon(kind)
	if sprite:canvas.draw_texture_rect(sprite,dest,false)

static func draw_landmarks(canvas:CanvasItem,camera:Vector2,region:String)->void:
	var footprint:Array=Transit.BUILDINGS[region]
	match region:
		"toucheng":
			building(canvas,camera,"toucheng",footprint[0],144)
			building(canvas,camera,"train",Transit.VEHICLES[region],104)
		"ruifang":
			building(canvas,camera,"ruifang",footprint[0],176)
			place(canvas,camera,"bus",Vector2(footprint[1].position.x,footprint[1].end.y-3.5),Vector2(160,112))
			place(canvas,camera,"bus",Vector2(footprint[1].end.x-5,footprint[1].end.y-3.5),Vector2(160,112))
			building(canvas,camera,"bus",Transit.VEHICLES[region],110)
		"jiufen":
			building(canvas,camera,"jiufen",footprint[0],168)
			building(canvas,camera,"jiufen",footprint[1],184)
			for x in [13,19,27,34]:
				place(canvas,camera,"lantern",Vector2(x,16),Vector2(64,64))

static func roadside(canvas:CanvasItem,at:Vector2,p:Vector2i,region:String,village_art:RefCounted)->void:
	if village_art==null:return
	match region:
		"toucheng":
			if p in [Vector2i(18,22),Vector2i(29,22),Vector2i(14,25)]:village_art.draw_prop(canvas,at,5,0.65)
		"ruifang":
			if p in [Vector2i(19,19),Vector2i(23,19),Vector2i(25,24),Vector2i(33,24)]:village_art.draw_prop(canvas,at,5,0.65)
		"jiufen":
			if p in [Vector2i(20,22),Vector2i(26,22),Vector2i(27,23),Vector2i(17,21)]:village_art.draw_prop(canvas,at,5,0.6)

static func building(canvas:CanvasItem,camera:Vector2,kind:String,footprint:Rect2i,height:int)->void:
	var width:=footprint.size.x*32
	place(canvas,camera,kind,Vector2(footprint.position.x,footprint.end.y-height/32.0),Vector2(width,height))

static func place(canvas:CanvasItem,camera:Vector2,kind:String,cell:Vector2,extent:Vector2)->void:
	draw_sprite(canvas,kind,Rect2((cell*32.0-camera).round(),extent))
