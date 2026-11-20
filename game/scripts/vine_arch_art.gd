extends RefCounted

const Industry=preload("res://scripts/industry.gd")
const WIDE=preload("res://assets/ui-life/vine-arch.png")
const TALL=preload("res://assets/ui-life/vine-arch-vertical.png")

static func image(color:String,vertical:=false)->AtlasTexture:
	var result:=AtlasTexture.new()
	result.atlas=TALL if vertical else WIDE
	result.region=region(color,vertical)
	return result

static func region(color:String,vertical:bool)->Rect2:
	var size:=Vector2(48,108) if vertical else Vector2(96,80)
	var index:=maxi(0,Industry.VINE_COLORS.keys().find(color))
	return Rect2(Vector2(index*size.x,0),size)

static func draw(canvas:CanvasItem,at:Vector2,color:String,vertical:=false,tint:=Color.WHITE,layer:="all")->void:
	var source:=region(color,vertical)
	var origin:=at+Vector2(-8,-12) if vertical else at+Vector2(0,-48)
	var crown:=58.0 if vertical else 42.0
	if layer=="crown":
		source.size.y=crown
	elif layer=="posts":
		source.position.y+=crown
		source.size.y-=crown
		origin.y+=crown
	canvas.draw_texture_rect_region(TALL if vertical else WIDE,Rect2(origin,source.size),source,tint)
