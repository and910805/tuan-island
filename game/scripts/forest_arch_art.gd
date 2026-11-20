extends RefCounted

const WIDE=preload("res://assets/ui-life/forest-arch.png")
const TALL=preload("res://assets/ui-life/forest-arch-vertical.png")
const WIDE_RISE:=46
const TALL_RISE:=31

static func draw(canvas:CanvasItem,at:Vector2,vertical:=false,tint:=Color.WHITE,layer:="all")->void:
	var art:=TALL if vertical else WIDE
	var source:=Rect2(Vector2.ZERO,art.get_size())
	var origin:=at+Vector2(-7,-TALL_RISE) if vertical else at+Vector2(0,-WIDE_RISE)
	var crown_height:=57.0 if vertical else 39.0
	if layer=="crown":
		source.size.y=crown_height
	elif layer=="posts":
		source.position.y=crown_height
		source.size.y-=crown_height
		origin.y+=crown_height
	canvas.draw_texture_rect_region(art,Rect2(origin,source.size),source,tint)
