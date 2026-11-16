extends RefCounted
## 玻璃爐 look (T067). Derived at load from the charcoal kiln cell of the real
## industry atlas PNG: the red brick becomes pale firebrick and the stoke hole
## holds a glass-green melt, so the two stations can be told apart in the world,
## the workshop shelf and the queue header. This is a recolour of generated art,
## not a new generated sprite; dedicated 32x48 furnace art is still pending.
const IndustryArt=preload("res://scripts/industry_art.gd")
const CELL:=Rect2i(96,64,32,48)
## Stoke hole area inside the 32x48 cell and the ember strip the kiln animates.
const MOUTH:=Rect2i(8,32,16,14)
const MELT:=Rect2(10,40,7,4)
static var body:Texture2D
static var tried:=false

static func texture() -> Texture2D:
	if tried:return body
	tried=true
	if not IndustryArt.load_atlas():return null
	var source:Image=IndustryArt.atlas.get_image()
	if source==null or source.is_empty():return null
	if source.is_compressed() and source.decompress()!=OK:return null
	var image:=source.get_region(CELL)
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var c:=image.get_pixel(x,y)
			if c.a<=0.0:continue
			image.set_pixel(x,y,recolor(c,MOUTH.has_point(Vector2i(x,y))))
	body=ImageTexture.create_from_image(image)
	return body

## Warm brick (red to orange, clearly saturated) turns into pale sand firebrick;
## embers in the stoke hole turn glass green. Outlines, soot and stone stay.
static func recolor(c:Color,in_mouth:bool) -> Color:
	var warm:=(c.h<0.13 or c.h>0.94) and c.s>0.28
	if not warm:return c
	if in_mouth and c.v>0.72 and c.s>0.5:
		return Color.from_hsv(0.46,0.42,minf(1.0,c.v*1.08),c.a)
	return Color.from_hsv(0.105,c.s*0.6,lerpf(c.v,1.0,0.2),c.a)

static func working(obj:Dictionary) -> bool:
	var processing=obj.get("processing",{})
	if not processing is Dictionary:return false
	var active=processing.get("active",{})
	return active is Dictionary and not active.is_empty()

static func draw(canvas:CanvasItem,at:Vector2,obj:Dictionary,time:float,reduced_motion:bool) -> void:
	var art:=texture()
	if art==null:
		IndustryArt.draw_device(canvas,at,"charcoal_kiln",{},time,reduced_motion)
		return
	canvas.draw_texture(art,at+Vector2(0,-16))
	if not working(obj):return
	var glow:=Color(1.25,1.3,1.25)
	if not reduced_motion and fposmod(time,1.2)<0.6:glow=Color(1.5,1.6,1.5)
	canvas.draw_texture_rect_region(art,Rect2(at+Vector2(0,-16)+MELT.position,MELT.size),MELT,glow)
