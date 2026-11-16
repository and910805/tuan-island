extends RefCounted

const PATH:="res://assets/mine-drill/atlas.png"
static var atlas:Texture2D
static var textures:Dictionary={}

static func icon(kind:String="machine")->Texture2D:
	if kind!="mine_drill_kit":return frame_texture(0)
	return texture_at(Rect2(0,192,32,32))

static func texture_at(region:Rect2)->Texture2D:
	if textures.has(region):return textures[region]
	if atlas==null and ResourceLoader.exists(PATH):atlas=load(PATH)
	if atlas==null:return null
	var image:=AtlasTexture.new()
	image.atlas=atlas
	image.region=region
	image.filter_clip=true
	textures[region]=image
	return image

static func frame_texture(index:int,direction:int=1)->Texture2D:
	return texture_at(Rect2(clampi(index,0,4)*48,posmod(direction,4)*48,48,48))

static func frame_for(obj:Dictionary,now:float,elapsed:float,reduced_motion:bool)->int:
	var job:Dictionary=obj.get("job",{})
	if reduced_motion or job.is_empty() or float(job.get("ready",0))<=now:return 0
	return 1+posmod(floori(elapsed*8.0),4)

static func draw(canvas:CanvasItem,at:Vector2,obj:Dictionary,now:float,elapsed:float,reduced_motion:bool)->void:
	if atlas==null and icon()==null:return
	var frame:=frame_for(obj,now,elapsed,reduced_motion)
	var facing:=posmod(int(obj.get("dir",1)),4)
	canvas.draw_texture_rect_region(atlas,Rect2(at-Vector2(8,8),Vector2(48,48)),Rect2(frame*48,facing*48,48,48))
