extends RefCounted
## Dedicated 32×48 glass furnace shared by the world, build preview and queue.
const FURNACE:=preload("res://assets/ui-inventory/glass-furnace.png")
const MELT:=Rect2(11,35,11,5)

static func texture() -> Texture2D:
	return FURNACE

static func working(obj:Dictionary) -> bool:
	var processing=obj.get("processing",{})
	if not processing is Dictionary:return false
	var active=processing.get("active",{})
	return active is Dictionary and not active.is_empty()

static func draw(canvas:CanvasItem,at:Vector2,obj:Dictionary,time:float,reduced_motion:bool) -> void:
	var art:=texture()
	canvas.draw_texture(art,at+Vector2(0,-16))
	if not working(obj):return
	var glow:=Color(1.25,1.3,1.25)
	if not reduced_motion and fposmod(time,1.2)<0.6:glow=Color(1.5,1.6,1.5)
	canvas.draw_texture_rect_region(art,Rect2(at+Vector2(0,-16)+MELT.position,MELT.size),MELT,glow)
