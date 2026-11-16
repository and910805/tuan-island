extends RefCounted

const PATH:="res://assets/lanyang-life/atlas.png"
const SOURCE=preload(PATH)
const PERSON:=Rect2(0,0,48,48)
const BLOCKAGE:=Rect2(48,0,32,32)
const SLUICE:=Rect2(80,0,32,32)
const NURSERY:=Rect2(112,0,32,32)

static func atlas() -> Texture2D:
	return SOURCE

static func portrait() -> Texture2D:
	var source:=atlas()
	if source==null:return null
	var result:=AtlasTexture.new()
	result.atlas=source
	result.region=Rect2(10,7,28,34)
	result.filter_clip=true
	return result

static func draw_person(canvas:CanvasItem,at:Vector2) -> void:
	var source:=atlas()
	if source:canvas.draw_texture_rect_region(source,Rect2(at+Vector2(-8,-18),Vector2(48,48)),PERSON)

static func draw_detail(canvas:CanvasItem,at:Vector2,kind:Rect2,elapsed:float,reduced_motion:bool) -> void:
	var source:=atlas()
	if source==null:return
	var bob:=roundf(sin(elapsed*1.4+at.y*0.1)) if kind==BLOCKAGE and not reduced_motion else 0.0
	canvas.draw_texture_rect_region(source,Rect2(at+Vector2(0,bob),Vector2(32,32)),kind)
