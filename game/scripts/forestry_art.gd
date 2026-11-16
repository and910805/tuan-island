extends RefCounted

const PATH:="res://assets/forestry/atlas.png"
const KIT:=Rect2(0,0,32,32)
const STATION:=Rect2(32,0,32,48)
const CHIPS:=Rect2(66,0,12,12)
const MARKER:=Rect2(66,12,12,12)
static var atlas:Texture2D
static var kit_texture:AtlasTexture

static func load_atlas() -> bool:
	if atlas==null and ResourceLoader.exists(PATH):atlas=load(PATH) as Texture2D
	return atlas!=null

static func icon(id:String) -> Texture2D:
	if id!="forester_kit" or not load_atlas():return null
	if kit_texture==null:
		kit_texture=AtlasTexture.new()
		kit_texture.atlas=atlas
		kit_texture.region=KIT
		kit_texture.filter_clip=true
	return kit_texture

static func draw_station(canvas:CanvasItem,at:Vector2,obj:Dictionary,time:float,reduced_motion:bool) -> void:
	if not load_atlas():return
	canvas.draw_texture_rect_region(atlas,Rect2(at+Vector2(0,-16),STATION.size),STATION)
	var last:=float(obj.get("last_cycle",-1))
	var age:=time-last
	if not obj.get("enabled",false) or last<0 or age<0 or age>1.5:return
	var travel:=Vector2.ZERO if reduced_motion else Vector2(roundf(age*4.0),-roundf(age*3.0))
	canvas.draw_texture_rect_region(atlas,Rect2(at+Vector2(17,8)+travel,Vector2(9,9)),CHIPS)

static func draw_plot_marker(canvas:CanvasItem,at:Vector2,tint:=Color.WHITE) -> void:
	if not load_atlas():return
	canvas.draw_texture_rect_region(atlas,Rect2(at+Vector2(19,20),MARKER.size),MARKER,tint)


static func draw_sapling(canvas:CanvasItem,at:Vector2,progress:float) -> void:
	if not load_atlas():return
	var source:=Rect2(0 if progress<0.5 else 32,48,32,32)
	canvas.draw_texture_rect_region(atlas,Rect2(at,Vector2(32,32)),source)
