extends RefCounted
const ForestryArt=preload("res://scripts/forestry_art.gd")
const SteamArt=preload("res://scripts/tea_revisit_art.gd")
const FinishFeedback=preload("res://scripts/processing_finish_feedback.gd")

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

static func processing_active(obj:Dictionary,time:float) -> bool:
	var queue=obj.get("processing")
	if queue is Dictionary:
		var active:Dictionary=queue.get("active",{})
		return not active.is_empty() and float(active.get("finish",0.0))>time
	var job:Dictionary=obj.get("job",{})
	return not job.is_empty() and float(job.get("ready",0.0))>time

static func finished_output(obj:Dictionary,kind:String,time:float) -> String:
	var item:="plank" if kind=="sawmill" else "charcoal"
	if int(obj.get("items",{}).get(item,0))>0:return item
	var queue=obj.get("processing")
	if queue is Dictionary:
		var active:Dictionary=queue.get("active",{})
		if not queue.get("ready",[]).is_empty() or (not active.is_empty() and float(active.get("finish",INF))<=time):return item
		return ""
	var job:Dictionary=obj.get("job",{})
	return item if not job.is_empty() and not job.get("auto",false) and float(job.get("ready",INF))<=time else ""

static func draw_device(canvas:CanvasItem,at:Vector2,kind:String,obj:Dictionary,time:float,reduced_motion:bool,tint:=Color.WHITE,elapsed:float=-1.0,finish_age:float=-1.0) -> void:
	var index:=DEVICES.find(kind)
	if index<0 or not load_atlas():return
	# Local time animates existing art between authoritative snapshots only.
	var phase_time:=time if elapsed<0.0 else elapsed
	canvas.draw_texture_rect_region(atlas,Rect2(at+Vector2(0,-16),Vector2(32,48)),Rect2(index*32,64,32,48),tint)
	if kind=="water_tank":
		var amount:=int(obj.get("water",0))
		if amount==0:
			# Tone down the water surface without touching the timber rim.
			var top:=Rect2(8,84,16,4)
			canvas.draw_texture_rect_region(atlas,Rect2(at+Vector2(8,4),top.size),top,Color("6d7470")*tint)
		elif not reduced_motion:
			# Two small reflections travel inside the water, never across the timber rim.
			for reflection in 2:
				var phase:=fposmod(phase_time*0.55+reflection*0.5,1.0)
				var glint:=Rect2(10,84,4,1)
				var color:=Color("defff6")*tint
				color.a*=sin(phase*PI)*0.8
				canvas.draw_texture_rect_region(atlas,Rect2(at+Vector2(8+roundf(phase*10),4+reflection*2),glint.size),glint,color)

	elif kind=="water_pump" and obj.get("enabled",false) and not reduced_motion:
		var travel:=roundf((sin(phase_time*TAU*1.4)+1.0)*1.5)
		device_detail(canvas,at,index,Rect2(24,21,3,4),Vector2(0,travel),tint)
	elif kind in ["sawmill","charcoal_kiln"]:
		var output:=finished_output(obj,kind,time)
		if not output.is_empty():
			var pad:=at+Vector2(22,16)
			canvas.draw_rect(Rect2(pad+Vector2(0,10),Vector2(13,4)),Color("593b2b")*tint)
			canvas.draw_rect(Rect2(pad+Vector2(1,10),Vector2(11,2)),Color("b28a59")*tint)
			var offset:=Vector2.ZERO if reduced_motion else FinishFeedback.output_offset(finish_age)
			canvas.draw_texture_rect(icon(output),Rect2(pad-Vector2(1,2)+offset,Vector2(16,16)),false,tint)
		if not processing_active(obj,time):return
		# Snapshot time decides whether work is real; local time only animates art.
		if kind=="sawmill" and not reduced_motion:
			var travel:=roundf(sin(phase_time*TAU*2.0)*2.0)
			device_detail(canvas,at,index,Rect2(12,26,5,4),Vector2(travel,0),Color.WHITE)
			if ForestryArt.load_atlas():
				for chip in 3:
					var phase:=fposmod(phase_time*1.6+float(chip)/3.0,1.0)
					var shift:=Vector2(roundf(phase*14.0),roundf(-sin(phase*PI)*6.0+phase*4.0))
					var color:=Color(1,1,1,1.0-smoothstep(0.5,1.0,phase))*tint
					canvas.draw_texture_rect_region(ForestryArt.atlas,Rect2(at+Vector2(17,13)+shift,Vector2(6,6)),ForestryArt.CHIPS,color)
		elif kind=="charcoal_kiln":
			var glow:=Color(1.30,1.13,0.92)
			if not reduced_motion:
				if fposmod(phase_time,1.2)<0.6:glow=Color(1.54,1.21,0.88)
				SteamArt.draw_steam(canvas,at+Vector2(16,-14),phase_time,false)
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

static func draw_pipe(canvas:CanvasItem,at:Vector2,mask:int,flowing:bool,time:float,reduced_motion:bool,elapsed:float=-1.0) -> void:
	var texture:=pipe_texture(mask&15)
	if texture==null:return
	var tint:=Color.WHITE
	if flowing:
		tint=Color("b2e2d2")
		if not reduced_motion:
			var phase_time:=time if elapsed<0.0 else elapsed
			# A soft sheen denotes available water, not a fabricated flow direction/rate.
			var sheen:=roundf((sin(phase_time*TAU/1.8)+1.0)*2.0)/4.0
			tint=tint.lerp(Color("c4f4e1"),sheen)
	canvas.draw_texture(texture,at,tint)
