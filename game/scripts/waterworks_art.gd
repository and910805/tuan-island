extends RefCounted

const PATH:="res://assets/waterworks/atlas.png"
static var atlas:Texture2D
static var icons:Dictionary={}

static func icon(kind:String="machine")->Texture2D:
	if icons.has(kind):return icons[kind]
	if atlas==null and ResourceLoader.exists(PATH):atlas=load(PATH)
	if atlas==null:return null
	var item:=AtlasTexture.new()
	item.atlas=atlas
	item.filter_clip=true
	item.region=Rect2(0,48,32,32) if kind=="waterworks_kit" else Rect2(0,0,48,48)
	icons[kind]=item
	return item

static func frame_for(obj:Dictionary,now:float,elapsed:float,reduced_motion:bool)->int:
	var job:Dictionary=obj.get("job",{})
	if reduced_motion or job.is_empty() or float(job.get("ready",0))<=now:return 0
	return 1+posmod(floori(elapsed*7.0),4)

static func draw(canvas:CanvasItem,at:Vector2,obj:Dictionary,now:float,elapsed:float,reduced_motion:bool)->void:
	if atlas==null and icon()==null:return
	var frame:=frame_for(obj,now,elapsed,reduced_motion)
	canvas.draw_texture_rect_region(atlas,Rect2(at+Vector2(-8,-16),Vector2(48,48)),Rect2(frame*48,0,48,48))
