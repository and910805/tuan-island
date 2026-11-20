extends RefCounted

const WIDE=preload("res://assets/ui-life/blue-stripe-awning.png")
const LONG=preload("res://assets/ui-life/blue-stripe-awning-vertical.png")
const SHADE:=Color(0.14,0.20,0.23,0.23)

static func span(vertical:bool)->Vector2:
	return Vector2(2,3) if vertical else Vector2(3,2)

static func opacity(tile:Vector2i,vertical:bool,player:Vector2,quiet:bool)->float:
	if not player.is_finite():return 1.0
	var local:=player-Vector2(tile)
	var size:=span(vertical)
	if quiet:return 0.37 if Rect2(Vector2.ZERO,size).has_point(local) else 1.0
	var edge:=minf(minf(local.x,local.y),minf(size.x-local.x,size.y-local.y))
	return lerpf(1.0,0.37,smoothstep(-0.24,0.40,edge))

static func draw_shadow(canvas:CanvasItem,at:Vector2,vertical:bool)->void:
	var size:=span(vertical)*32.0
	canvas.draw_colored_polygon(PackedVector2Array([
		at+Vector2(8,10),at+Vector2(size.x-4,10),
		at+size-Vector2(1,4),at+Vector2(12,size.y-4),
	]),SHADE)

static func draw_canopy(canvas:CanvasItem,at:Vector2,vertical:bool,tint:=Color.WHITE,roof_opacity:=1.0)->void:
	var art:=LONG if vertical else WIDE
	var size:=art.get_size()
	var position:=at.round()+Vector2(1,span(vertical).y*32.0-4.0-size.y)
	if roof_opacity>=1.0:
		canvas.draw_texture(art,position,tint)
		return
	var hem:=56.0 if vertical else 33.0
	var roof:=Rect2(0,0,size.x,hem)
	var posts:=Rect2(0,hem,size.x,size.y-hem)
	canvas.draw_texture_rect_region(art,Rect2(position,roof.size),roof,Color(tint,tint.a*roof_opacity))
	canvas.draw_texture_rect_region(art,Rect2(position+posts.position,posts.size),posts,tint)
