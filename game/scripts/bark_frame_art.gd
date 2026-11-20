@static_unload
extends RefCounted

const Codec=preload("res://scripts/bark_frame.gd")
const Keepsake=preload("res://scripts/resident_keepsake_art.gd")
const FRAME=preload("res://assets/ui-life/bark-picture-frame.png")
const SKETCH_REGION:=Rect2(9,7,14,11)
const CACHE_CAPACITY:=32
static var photos:Dictionary={}
static var sketch:AtlasTexture

static func content(value:String)->Texture2D:
	if value==Codec.SKETCH:
		if sketch==null:
			sketch=AtlasTexture.new()
			sketch.atlas=Keepsake.piece("keepsake_diandian")
			sketch.region=SKETCH_REGION
			sketch.filter_clip=true
		return sketch
	if value.is_empty():return null
	if photos.has(value):return photos[value]
	var raw:=Codec.photo_bytes(value)
	if raw.is_empty():return null
	var image:=Image.create_empty(Codec.SIZE.x,Codec.SIZE.y,false,Image.FORMAT_RGB8)
	for y in Codec.SIZE.y:
		for x in Codec.SIZE.x:
			var pixel:=raw.decode_u16((y*Codec.SIZE.x+x)*2)
			image.set_pixel(x,y,Color(float(pixel>>11)/31.0,float((pixel>>5)&63)/63.0,float(pixel&31)/31.0))
	var texture:=ImageTexture.create_from_image(image)
	if photos.size()>=CACHE_CAPACITY:photos.erase(photos.keys()[0])
	photos[value]=texture
	return texture

static func draw(canvas:CanvasItem,at:Vector2,value:="",tint:=Color.WHITE)->void:
	canvas.draw_texture(FRAME,at,tint)
	var picture:=content(value)
	if picture!=null:
		canvas.draw_texture_rect(picture,Rect2(at+Vector2(6,5),Vector2(20,12)),false,tint)
