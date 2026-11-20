extends RefCounted
## Own-stall render accents (pure presentation). Drawn over the 64x64 market stall
## texture with whole-pixel rects only (no filtering, no scaling), in screen space.
##  cloth: a 3px runner on the plain wooden front panel, under the existing towel
##         (towel ends at y48) and clear of the counter-top tags (y24..36).
##  sign:  a small charm hanging in the empty air beside the right awning post,
##         clear of the tags, baskets and the coin icon.
## "natural" cloth and "plain" sign draw nothing, so the default look is unchanged.

const CLOTHS:=["natural","indigo","leaf","chestnut"]
const SIGNS:=["plain","windbell","flower","chestnut_badge"]
const RUNNER:=Rect2i(14,49,36,3)
const CHARM_X:=56
const CHARM_Y:=21
const StallArt=preload("res://scripts/flower_scene_art.gd")
static var _chestnut_awning:Texture2D

class Preview extends Control:
	var decor:Dictionary
	var paint:Callable

	func _init(style:Dictionary,painter:Callable)->void:
		decor=style
		paint=painter
		custom_minimum_size=Vector2(128,128)
		size_flags_vertical=Control.SIZE_SHRINK_CENTER
		texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_filter=Control.MOUSE_FILTER_IGNORE

	func _draw()->void:
		draw_set_transform(Vector2.ZERO,0.0,Vector2(2,2))
		draw_texture(StallArt.market_texture(false),Vector2.ZERO)
		paint.call(self,Vector2.ZERO,decor)

static func preview(decor:Dictionary)->Control:
	return Preview.new(decor,draw)

static func normalize(decor:Variant) -> Dictionary:
	var source:Dictionary=decor if decor is Dictionary else {}
	var cloth:=str(source.get("cloth","natural"))
	var sign:=str(source.get("sign","plain"))
	return {"cloth":cloth if cloth in CLOTHS else "natural","sign":sign if sign in SIGNS else "plain"}

static func _px(canvas:CanvasItem,origin:Vector2,x:int,y:int,w:int,h:int,color:Color,alpha:float) -> void:
	color.a*=alpha
	canvas.draw_rect(Rect2(origin+Vector2(x,y),Vector2(w,h)),color)

## origin: top-left of the stall texture in canvas coordinates (already pixel-snapped).
static func draw(canvas:CanvasItem,origin:Vector2,decor:Variant,alpha:=1.0) -> void:
	var look:=normalize(decor)
	var snapped_origin:=origin.round()
	match look.cloth:
		"indigo":_draw_runner(canvas,snapped_origin,alpha,Color(0.17,0.22,0.43),Color(0.28,0.35,0.60),Color(0.90,0.88,0.78),false)
		"leaf":_draw_runner(canvas,snapped_origin,alpha,Color(0.36,0.50,0.30),Color(0.27,0.39,0.23),Color(0.78,0.86,0.55),true)
		"chestnut":_draw_chestnut_cloth(canvas,snapped_origin,alpha)
	match look.sign:
		"windbell":_draw_windbell(canvas,snapped_origin,alpha)
		"flower":_draw_flower(canvas,snapped_origin,alpha)
		"chestnut_badge":_draw_chestnut_badge(canvas,snapped_origin,alpha)

## 栗棕攤布: chestnut runner, darker hem, cream stitch dashes with a husk-spike notch row.
static func _draw_chestnut_cloth(canvas:CanvasItem,origin:Vector2,alpha:float) -> void:
	if _chestnut_awning==null:
		var source:=StallArt.market_texture(false).get_image()
		var overlay:=Image.create_empty(source.get_width(),source.get_height(),false,Image.FORMAT_RGBA8)
		# Recolour the olive stripes while keeping the original canvas folds and cream stripes.
		for y in range(10,24):
			for x in range(source.get_width()):
				var pixel:=source.get_pixel(x,y)
				if pixel.a>0.0 and pixel.h>0.132 and pixel.h<0.23 and pixel.s>0.17:
					overlay.set_pixel(x,y,Color.from_hsv(0.052,minf(0.70,pixel.s+0.22),pixel.v,pixel.a))
		_chestnut_awning=ImageTexture.create_from_image(overlay)
	canvas.draw_texture(_chestnut_awning,origin,Color(1,1,1,alpha))
	var r:=RUNNER
	var base:=Color(0.48,0.28,0.16)
	var edge:=Color(0.30,0.17,0.10)
	var stitch:=Color(0.93,0.80,0.52)
	_px(canvas,origin,r.position.x,r.position.y,r.size.x,r.size.y,base,alpha)
	_px(canvas,origin,r.position.x,r.position.y,r.size.x,1,edge,alpha)
	_px(canvas,origin,r.position.x,r.position.y+r.size.y-1,r.size.x,1,edge,alpha)
	for x in range(r.position.x+2,r.position.x+r.size.x-2,6):
		_px(canvas,origin,x,r.position.y+1,2,1,stitch,alpha)
		_px(canvas,origin,x+3,r.position.y+2,1,1,stitch,alpha)
	_px(canvas,origin,r.position.x,r.position.y,1,r.size.y,edge,alpha)
	_px(canvas,origin,r.position.x+r.size.x-1,r.position.y,1,r.size.y,edge,alpha)

## 栗果招牌: a hanging chestnut with a cream cap tip and a green leaf, same slot as the other charms.
static func _draw_chestnut_badge(canvas:CanvasItem,origin:Vector2,alpha:float) -> void:
	var string:=Color(0.45,0.32,0.20)
	var husk:=Color(0.36,0.20,0.11)
	var nut:=Color(0.58,0.34,0.18)
	var shine:=Color(0.80,0.58,0.36)
	var tip:=Color(0.93,0.80,0.52)
	var leaf:=Color(0.40,0.56,0.30)
	var x:=CHARM_X
	var y:=CHARM_Y
	_px(canvas,origin,x,y,1,4,string,alpha)
	_px(canvas,origin,x-5,y+4,11,9,husk,alpha)
	_px(canvas,origin,x-4,y+5,9,7,Color("d4ab6b"),alpha)
	_px(canvas,origin,x-1,y+4,3,1,husk,alpha)
	_px(canvas,origin,x-2,y+5,5,4,nut,alpha)
	_px(canvas,origin,x-1,y+9,3,1,nut,alpha)
	_px(canvas,origin,x-2,y+5,5,1,husk,alpha)
	_px(canvas,origin,x-1,y+6,1,2,shine,alpha)
	_px(canvas,origin,x,y+10,1,1,tip,alpha)
	_px(canvas,origin,x+1,y+3,2,1,leaf,alpha)

static func _draw_runner(canvas:CanvasItem,origin:Vector2,alpha:float,base:Color,edge:Color,mark:Color,leafy:bool) -> void:
	var r:=RUNNER
	_px(canvas,origin,r.position.x,r.position.y,r.size.x,r.size.y,base,alpha)
	_px(canvas,origin,r.position.x,r.position.y,r.size.x,1,edge,alpha)
	_px(canvas,origin,r.position.x,r.position.y+r.size.y-1,r.size.x,1,edge,alpha)
	for x in range(r.position.x+2,r.position.x+r.size.x-1,4):
		if leafy:
			# tiny leaf: two diagonal pixels on the middle row plus one above-left tip
			_px(canvas,origin,x,r.position.y+1,2,1,mark,alpha)
		else:
			# indigo resist-dye dot pair
			_px(canvas,origin,x,r.position.y+1,1,1,mark,alpha)
	# fringe-free hem ends: darker end caps keep the runner reading as folded cloth
	_px(canvas,origin,r.position.x,r.position.y,1,r.size.y,edge,alpha)
	_px(canvas,origin,r.position.x+r.size.x-1,r.position.y,1,r.size.y,edge,alpha)

static func _draw_windbell(canvas:CanvasItem,origin:Vector2,alpha:float) -> void:
	var string:=Color(0.45,0.32,0.20)
	var glass:=Color(0.62,0.82,0.88)
	var shade:=Color(0.38,0.58,0.68)
	var paper:=Color(0.96,0.90,0.70)
	var x:=CHARM_X
	var y:=CHARM_Y
	_px(canvas,origin,x,y,1,3,string,alpha)
	_px(canvas,origin,x-1,y+3,3,1,glass,alpha)
	_px(canvas,origin,x-2,y+4,5,2,glass,alpha)
	_px(canvas,origin,x-2,y+6,5,1,shade,alpha)
	_px(canvas,origin,x,y+7,1,2,string,alpha)
	_px(canvas,origin,x,y+9,1,1,shade,alpha)
	_px(canvas,origin,x-1,y+10,3,3,paper,alpha)
	_px(canvas,origin,x,y+11,1,1,shade,alpha)

static func _draw_flower(canvas:CanvasItem,origin:Vector2,alpha:float) -> void:
	var string:=Color(0.45,0.32,0.20)
	var petal:=Color(0.93,0.62,0.70)
	var centre:=Color(0.98,0.84,0.38)
	var leaf:=Color(0.40,0.56,0.30)
	var x:=CHARM_X
	var y:=CHARM_Y
	_px(canvas,origin,x,y,1,5,string,alpha)
	_px(canvas,origin,x,y+5,1,1,petal,alpha)
	_px(canvas,origin,x-1,y+6,3,3,petal,alpha)
	_px(canvas,origin,x,y+9,1,1,petal,alpha)
	_px(canvas,origin,x,y+7,1,1,centre,alpha)
	_px(canvas,origin,x+1,y+10,2,1,leaf,alpha)
	_px(canvas,origin,x-2,y+11,2,1,leaf,alpha)
