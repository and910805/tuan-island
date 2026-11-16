extends RefCounted

const PATH:="res://assets/bobo/atlas.png"
const TRAY_PATH:="res://assets/bobo/tray.png"
const REGIONS:={"person":0,"portrait":1,"table":2,"ore_display":3,"coarse":4,"medium":5,"fine":6,"lantern":7}
static var atlas:Texture2D

static func texture() -> Texture2D:
	if atlas==null and ResourceLoader.exists(PATH):atlas=load(PATH)
	return atlas

static func region(kind:String) -> Rect2:
	var index:int=REGIONS[kind]
	return Rect2((index%4)*48,(index>>2)*48,48,48)

static func icon(kind:String) -> Texture2D:
	if kind=="tray":return load(TRAY_PATH) as Texture2D if ResourceLoader.exists(TRAY_PATH) else null
	if not REGIONS.has(kind) or texture()==null:return null
	var sprite:=AtlasTexture.new()
	sprite.atlas=atlas
	sprite.region=region(kind)
	return sprite

static func draw(canvas:CanvasItem,at:Vector2,kind:String) -> bool:
	if not REGIONS.has(kind) or texture()==null:return false
	canvas.draw_texture_rect_region(atlas,Rect2(at,Vector2(48,48)),region(kind))
	return true
