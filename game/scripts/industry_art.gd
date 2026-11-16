extends RefCounted

const PATH:="res://assets/industry/atlas.png"
const ITEMS:=["plank","resin","charcoal","pipe_kit","tank_kit","pump_kit","sawmill_kit","kiln_kit"]
const DEVICES:=["water_tank","water_pump","sawmill","charcoal_kiln"]
static var atlas:Texture2D
static var icons:Dictionary={}
static var pipes:Dictionary={}

static func load_atlas() -> bool:
	if atlas==null and ResourceLoader.exists(PATH):atlas=load(PATH) as Texture2D
	return atlas!=null

static func icon(id:String) -> Texture2D:
	if icons.has(id):return icons[id]
	var index:=ITEMS.find(id)
	if index<0 or not load_atlas():return null
	var region:=AtlasTexture.new()
	region.atlas=atlas
	region.region=Rect2((index%4)*32,(index/4)*32,32,32)
	region.filter_clip=true
	icons[id]=region
	return region

static func draw_device(canvas:CanvasItem,at:Vector2,kind:String,obj:Dictionary,time:float,reduced_motion:bool) -> void:
	var index:=DEVICES.find(kind)
	if index<0 or not load_atlas():return
	canvas.draw_texture_rect_region(atlas,Rect2(at+Vector2(0,-16),Vector2(32,48)),Rect2(index*32,64,32,48))
	if kind=="water_tank":
		var amount:=int(obj.get("water",0))
		if amount==0:
			# Tone down the water surface without touching the timber rim.
			var top:=Rect2(8,84,16,4)
			canvas.draw_texture_rect_region(atlas,Rect2(at+Vector2(8,4),top.size),top,Color("6d7470"))
		elif not reduced_motion and fposmod(time,2.0)<0.4:
			var glint:=Rect2(10,84,8,2)
			canvas.draw_texture_rect_region(atlas,Rect2(at+Vector2(11,4),glint.size),glint,Color("defff6"))

	elif kind=="water_pump" and obj.get("enabled",false) and not reduced_motion:
		var travel:=1 if fposmod(time,1.2)<0.6 else 0
		device_detail(canvas,at,index,Rect2(24,21,3,4),Vector2(0,travel),Color.WHITE)
	elif kind in ["sawmill","charcoal_kiln"]:
		var job:Dictionary=obj.get("job",{})
		if job.is_empty() or time>=float(job.get("ready",0)):return
		if kind=="sawmill" and not reduced_motion:
			var travel:=1 if fposmod(time,0.8)<0.4 else 0
			device_detail(canvas,at,index,Rect2(12,26,5,4),Vector2(travel,0),Color.WHITE)
		elif kind=="charcoal_kiln":
			var glow:=Color(1.30,1.13,0.92)
			if not reduced_motion and fposmod(time,1.2)<0.6:glow=Color(1.54,1.21,0.88)
			device_detail(canvas,at,index,Rect2(10,40,7,4),Vector2.ZERO,glow)

static func device_detail(canvas:CanvasItem,at:Vector2,column:int,detail:Rect2,offset:Vector2,tint:Color) -> void:
	var source:=Rect2(detail.position+Vector2(column*32,64),detail.size)
	var destination:=Rect2(at+Vector2(0,-16)+detail.position+offset,detail.size)
	canvas.draw_texture_rect_region(atlas,destination,source,tint)

static func pipe_texture(mask:int) -> Texture2D:
	if pipes.has(mask):return pipes[mask]
	if not load_atlas():return null
	var column:=0
	var rotation:=0
	match mask:
		1:rotation=1
		2:rotation=2
		4:rotation=3
		5:rotation=1
		3,6,12,9:
			column=1
			rotation=[3,6,12,9].find(mask)
		11,7,14,13:
			column=2
			rotation=[11,7,14,13].find(mask)
		15:column=3
	var image:=atlas.get_image().get_region(Rect2i(column*32,112,32,32))
	if mask==0:
		var middle:=image.get_region(Rect2i(8,0,16,32))
		image.fill(Color.TRANSPARENT)
		image.blit_rect(middle,Rect2i(0,0,16,32),Vector2i(8,0))
	elif mask in [1,2,4,8]:
		# The right flange becomes a capped center, with only the left connection continuing.
		var half:=image.get_region(Rect2i(16,0,16,32))
		image.fill(Color.TRANSPARENT)
		image.blit_rect(half,Rect2i(0,0,16,32),Vector2i(0,0))
	for turn in range(rotation):image.rotate_90(CLOCKWISE)
	pipes[mask]=ImageTexture.create_from_image(image)
	return pipes[mask]

static func draw_pipe(canvas:CanvasItem,at:Vector2,mask:int,flowing:bool,time:float,reduced_motion:bool) -> void:
	var texture:=pipe_texture(mask&15)
	if texture==null:return
	var tint:=Color.WHITE
	if flowing:
		tint=Color("b2e2d2") if reduced_motion or fposmod(time,1.1)>0.35 else Color("c4f4e1")
	canvas.draw_texture(texture,at,tint)
