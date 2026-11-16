extends RefCounted

const ATLAS_PATH:="res://assets/station-life/atlas.png"
const AREAS:=["toucheng","ruifang","jiufen"]
const CORNERS:={"toucheng":Vector2i(20,21),"ruifang":Vector2i(23,25),"jiufen":Vector2i(22,20)}
static var atlas:Texture2D
static var frames:Dictionary={}

static func sprite(index:int)->Texture2D:
	if frames.has(index):return frames[index]
	if atlas==null and ResourceLoader.exists(ATLAS_PATH):atlas=load(ATLAS_PATH)
	if atlas==null:return null
	var frame:=AtlasTexture.new()
	frame.atlas=atlas
	frame.region=Rect2((index%3)*48,(index/3)*48,48,48)
	frame.filter_clip=true
	frames[index]=frame
	return frame

static func portrait(region:String)->Texture2D:
	var index:=AREAS.find(region)
	return sprite(index+3) if index>=0 else null

static func draw_person(canvas:CanvasItem,foot:Vector2,region:String,time:float,reduced_motion:bool)->void:
	var index:=AREAS.find(region)
	if index<0:return
	var art:=sprite(index)
	if art:
		var idle_offset:=0.0 if reduced_motion or fposmod(time+index,5.0)>0.26 else -1.0
		canvas.draw_texture(art,foot+Vector2(-24,-44+idle_offset))

static func draw_corner(canvas:CanvasItem,at:Vector2,repaired:bool)->void:
	var bench:=sprite(7 if repaired else 6)
	if bench:canvas.draw_texture(bench,at+Vector2(-8,-16))
	if repaired:
		var pot:=sprite(8)
		if pot:canvas.draw_texture(pot,at+Vector2(-20,-12))
