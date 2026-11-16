@static_unload
extends RefCounted

const Terrain=preload("res://assets/village-preview/terrain.png")
const Props=preload("res://assets/village-preview/props.png")
const Furnishings=preload("res://assets/ui-life/furniture.png")
const Furniture=preload("res://scripts/furniture_sprite_art.gd")
const AtlasPath:="res://assets/tea-ceramics/items.png"
const BuildingsPath:="res://assets/tea-ceramics/buildings.png"
const ICONS:=["tea_leaf","clay","tea_jar","tea_light","tea_deep","fiber_packet","wrapped_jar","tea_bush"]
static var atlas:Texture2D
static var buildings:Texture2D
static var icons:Dictionary={}

static func clear_cache()->void:
	icons.clear()
	atlas=null
	buildings=null

static func icon(id:String)->Texture2D:
	if id=="tea_returned_jar":id="tea_jar"
	if id in ["tea_worn_jar","tea_spent_jar"]:
		if icons.has(id):return icons[id]
		var worn:=AtlasTexture.new()
		worn.atlas=load("res://assets/tea-ceramics/wear.png")
		worn.region=Rect2(0 if id=="tea_worn_jar" else 32,0,32,32)
		worn.filter_clip=true
		icons[id]=worn
		return worn
	if icons.has(id):return icons[id]
	var index:=ICONS.find(id)
	if index<0 or not ResourceLoader.exists(AtlasPath):return null
	if atlas==null:atlas=load(AtlasPath) as Texture2D
	var texture:=AtlasTexture.new()
	texture.atlas=atlas
	texture.region=Rect2(index*32,0,32,32)
	texture.filter_clip=true
	icons[id]=texture
	return texture

static func ground(canvas:CanvasItem,at:Vector2,cell:Vector2i,region:String,land:bool)->void:
	var tea:=region=="maokong"
	var lane:=cell.y in range(19,22) or (cell.x in range(22,25) and cell.y in range(21,27))
	var material:=6
	var tint:=Color("566d57") if tea else Color("71675d")
	if land:
		if tea:
			material=4 if lane else (6 if cell.y in [23,25,27,29] and cell.x in range(24,34) else 0)
			tint=Color("ccb292") if lane else Color("a2b481")
		else:
			material=11 if lane else 4
			tint=Color("d9b19a") if lane else Color("b19679")
		if cell.y in [17,18] and cell.x in range(18,29):
			material=10 if tea else 11
			tint=Color("b5a181") if tea else Color("9c7460")
	var region_rect:=Rect2((material%4)*32,(material>>2)*32,32,32)
	canvas.draw_texture_rect_region(Terrain,Rect2(at,Vector2(32,32)),region_rect,tint)

static func draw_site(canvas:CanvasItem,at:Vector2,site:String)->void:
	match site:
		"roast":
			canvas.draw_texture_rect_region(Furnishings,Rect2(at+Vector2(-16,-38),Vector2(64,64)),Rect2(0,112,32,32),Color("e1c9a3"))
		"kiln":
			Furniture.draw_sprite(canvas,at,"table")
			var jar:=icon("tea_jar")
			if jar:canvas.draw_texture_rect(jar,Rect2(at+Vector2(0,-15),Vector2(32,32)),false)
		"pack":Furniture.draw_sprite(canvas,at,"table")
		"clay","pick":
			var texture:=icon("tea_bush" if site=="pick" else "clay")
			if texture:canvas.draw_texture_rect(texture,Rect2(at,Vector2(32,32)),false)

static func draw_backdrop(canvas:CanvasItem,origin:Vector2,region:String)->void:
	var tea:=region=="maokong"
	for x in range(9,37,3):
		prop(canvas,origin,Vector2i(x,14),(x/3)%4)
	for cell in [Vector2i(10,17),Vector2i(14,18),Vector2i(32,16),Vector2i(35,18),Vector2i(34,28),Vector2i(17,28)]:
		prop(canvas,origin,cell,4 if tea else 6)
	if tea:
		building(canvas,origin,Vector2i(18,14),0)
		prop(canvas,origin,Vector2i(23,17),4)
		prop(canvas,origin,Vector2i(26,17),5)
		prop(canvas,origin,Vector2i(28,17),10)
		var bush:=icon("tea_bush")
		if bush:
			for y in [25,27,29]:
				for x in range(25,34,2):
					canvas.draw_texture_rect(bush,Rect2(origin+Vector2(x,y)*32,Vector2(32,32)),false,Color("c0cead"))
	else:
		building(canvas,origin,Vector2i(18,14),1)
		building(canvas,origin,Vector2i(23,14),2)
		prop(canvas,origin,Vector2i(29,17),10)
		Furniture.draw_sprite(canvas,origin+Vector2(27,19)*32,"window")
		Furniture.draw_sprite(canvas,origin+Vector2(29,19)*32,"bench")
		for x in [27,29]:
			var jar:=icon("tea_jar")
			if jar:canvas.draw_texture_rect(jar,Rect2(origin+Vector2(x*32,19*32-14),Vector2(32,32)),false)

static func building(canvas:CanvasItem,origin:Vector2,cell:Vector2i,index:int)->void:
	if buildings==null and ResourceLoader.exists(BuildingsPath):
		buildings=load(BuildingsPath) as Texture2D
	if buildings==null:return
	var at:=origin+Vector2(cell)*32
	canvas.draw_texture_rect_region(buildings,Rect2(at,Vector2(128,128)),Rect2(index*128,0,128,128))

static func draw_feedback(canvas:CanvasItem,at:Vector2,site:String,record:Dictionary,now:float,elapsed:float,reduced_motion:bool)->void:
	match site:
		"roast","kiln":
			var job:Dictionary=record.get(site,{})
			if job.is_empty():return
			if now<float(job.ready):
				draw_heat(canvas,at+Vector2(16,-12),site=="kiln",elapsed,reduced_motion)
			else:
				draw_status_icon(canvas,at+Vector2(23,-17),"tea_jar" if site=="kiln" else "tea_"+str(job.style))
		"pack":
			var packed:Dictionary=record.get("packed",{})
			var outbound:Dictionary=record.get("outbound",{})
			var returning:Dictionary=record.get("returning",{})
			if not packed.is_empty() or not outbound.is_empty():
				var parcel:=packed if not packed.is_empty() else outbound
				var label_offset:=Vector2(-4,-14) if not packed.is_empty() else Vector2(-13,-13)
				draw_status_icon(canvas,at+label_offset,"fiber_packet" if parcel.wrap=="fiber" else "wrapped_jar",Color.WHITE if not packed.is_empty() or now>=float(outbound.ready) else Color(1,1,1,0.55))
			if not returning.is_empty():
				var items:Dictionary=returning.get("items",{})
				var returned_icon:="tea_spent_jar" if int(items.get("tea_spent_jar",0))>0 else ("tea_worn_jar" if int(items.get("tea_worn_jar",0))>0 else "tea_jar")
				draw_status_icon(canvas,at+Vector2(22,-14),returned_icon,Color.WHITE if now>=float(returning.ready) else Color(1,1,1,0.48))

static func draw_status_icon(canvas:CanvasItem,at:Vector2,id:String,tint:=Color.WHITE)->void:
	var texture:=icon(id)
	if texture:canvas.draw_texture_rect(texture,Rect2(at.round(),Vector2(32,32)),false,tint)

static func draw_heat(canvas:CanvasItem,at:Vector2,kiln:bool,elapsed:float,reduced_motion:bool)->void:
	for index in range(3):
		var phase:=float(index)*0.25 if reduced_motion else fposmod(elapsed*(1.25 if kiln else 0.85)+index*0.29,1.0)
		var point:=(at+Vector2(index*4-4+sin(phase*TAU)*2.0,-4.0-phase*16.0)).round()
		var tint:=Color("ffc36a") if kiln else Color("f6e5c6")
		tint.a=0.82-phase*0.57
		canvas.draw_rect(Rect2(point,Vector2(2,2)),tint)
		if not kiln:canvas.draw_rect(Rect2(point+Vector2(1,-1),Vector2(2,1)),tint)

static func prop(canvas:CanvasItem,origin:Vector2,cell:Vector2i,index:int)->void:
	var at:=origin+Vector2(cell)*32
	canvas.draw_texture_rect_region(Props,Rect2(at+Vector2(-16,-35),Vector2(64,64)),Rect2((index%4)*64,(index>>2)*64,64,64))
