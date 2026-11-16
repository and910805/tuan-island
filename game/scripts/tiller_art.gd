extends RefCounted

const PATH:="res://assets/tiller/atlas.png"
static var atlas:Texture2D
static var tool_icon:AtlasTexture

static func load_atlas() -> bool:
	if atlas==null and ResourceLoader.exists(PATH):atlas=load(PATH) as Texture2D
	return atlas!=null

static func icon(id:String) -> Texture2D:
	if id!="tiller" or not load_atlas():return null
	if tool_icon==null:
		tool_icon=AtlasTexture.new()
		tool_icon.atlas=atlas
		tool_icon.region=Rect2(96,0,32,32)
		tool_icon.filter_clip=true
	return tool_icon

static func draw_machine(canvas:CanvasItem,at:Vector2,facing:Vector2i,time:float,working:bool,reduced_motion:bool) -> void:
	if not load_atlas():return
	var column:=2
	match facing:
		Vector2i.UP:column=0
		Vector2i.LEFT:column=1
		Vector2i.RIGHT:column=3
	var row:=posmod(floori(time*6.0),2) if working and not reduced_motion else 0
	canvas.draw_texture_rect_region(atlas,Rect2(at.round()-Vector2(16,30),Vector2(32,32)),Rect2(column*32,row*32,32,32))
