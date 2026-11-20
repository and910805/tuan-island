extends RefCounted
## Sea-breeze fair stall accents (pure presentation, original pixel art, no assets).
## Drawn over the 64x64 market stall texture with whole-pixel rects only, in screen
## space, BEFORE the shelf tags / summer sign / coin / label so those stay on top.
## Reserved areas kept clear (stall-texture coordinates):
##   item tags x8..56,y24..36   summer sign x2..20,y6..26   till coin x46..62,y2..18
##   own-market runner x14..50,y49..52 (cloth trim sits just below it)
## Layout: two sail flags on small poles (x23 / x43, y1..10) with bunting between
## them, a wave-and-sail cloth trim y53..56, a gull motif, and after 3 samples a
## gold star marker (x29..35,y12..18). Wind is a 2-frame tip flutter; reduced_motion
## and screenshot mode hold frame 0.

const PHASES:=["visit","return"]
const MAX_SERVED:=3
const POLE_L:=23
const POLE_R:=43
const BUNTING_Y:=4
const TRIM:=Rect2i(14,53,36,4)

const POLE:=Color(0.45,0.32,0.20)
const SAIL:=Color(0.97,0.95,0.86)
const SAIL_SHADE:=Color(0.80,0.86,0.88)
const TEAL:=Color(0.16,0.62,0.70)
const DEEP:=Color(0.12,0.34,0.55)
const CORAL:=Color(0.93,0.42,0.36)
const SUN:=Color(0.98,0.82,0.30)
const SUN_EDGE:=Color(0.72,0.50,0.14)
const FOAM:=Color(0.92,0.97,0.96)

## True when the personal sea-breeze fair is ongoing and the stall should be dressed.
static func shows(fair:Variant) -> bool:
	if not fair is Dictionary:return false
	return bool(fair.get("active",false)) and str(fair.get("phase","")) in PHASES

static func served_count(fair:Variant) -> int:
	if not fair is Dictionary:return 0
	return clampi(int(fair.get("served",0)),0,MAX_SERVED)

static func wind_frame(elapsed:float,still:bool) -> int:
	if still or not is_finite(elapsed) or elapsed<0.0:return 0
	return int(floorf(elapsed*1.6))%2

static func _px(canvas:CanvasItem,origin:Vector2,x:int,y:int,w:int,h:int,color:Color,alpha:float) -> void:
	color.a*=alpha
	canvas.draw_rect(Rect2(origin+Vector2(x,y),Vector2(w,h)),color)

## origin: top-left of the stall texture (pixel-snapped here). Returns true if drawn.
static func draw(canvas:CanvasItem,origin:Vector2,fair:Variant,elapsed:=0.0,still:=false,alpha:=1.0) -> bool:
	if not shows(fair):return false
	var base:=origin.round()
	var frame:=wind_frame(elapsed,still)
	_draw_trim(canvas,base,alpha)
	_draw_bunting(canvas,base,alpha,frame)
	_draw_sail(canvas,base,POLE_L,1,alpha,frame,CORAL)
	_draw_sail(canvas,base,POLE_R,-1,alpha,frame,TEAL)
	_draw_gull(canvas,base,alpha,frame)
	if served_count(fair)>=MAX_SERVED:_draw_marker(canvas,base,alpha)
	return true

## Pole with a small triangular sail leaning toward `dir` (+1 right / -1 left).
static func _draw_sail(canvas:CanvasItem,o:Vector2,x:int,dir:int,alpha:float,frame:int,color:Color) -> void:
	_px(canvas,o,x,1,1,10,POLE,alpha)
	_px(canvas,o,x,0,1,1,SUN,alpha)
	var sx:=x+1 if dir>0 else x-1
	var widths:=[1,2,3,4] if frame==0 else [1,2,3,3]
	for i in widths.size():
		var w:int=widths[i]
		var left:=sx if dir>0 else sx-w+1
		_px(canvas,o,left,2+i,w,1,color if i<3 else SAIL_SHADE,alpha)
	# white hem on the mast side
	_px(canvas,o,sx,2,1,4,SAIL,alpha)

static func _draw_bunting(canvas:CanvasItem,o:Vector2,alpha:float,frame:int) -> void:
	var colors:=[CORAL,SUN,TEAL,FOAM,CORAL,SUN]
	var from:=POLE_L+3
	var to:=POLE_R-3
	for x in range(from,to+1):
		var sag:=int(round(sin(float(x-from)/float(to-from)*PI)*1.0))
		_px(canvas,o,x,BUNTING_Y+sag,1,1,POLE,alpha)
	var index:=0
	for x in range(from+1,to-1,3):
		var sag:=int(round(sin(float(x-from)/float(to-from)*PI)*1.0))
		var flap:=1 if (frame==1 and index%2==0) else 0
		var top:=BUNTING_Y+sag+1
		var color:Color=colors[index%colors.size()]
		_px(canvas,o,x,top,2,1,color,alpha)
		_px(canvas,o,x+flap,top+1,2 if flap==0 else 1,1,color,alpha)
		index+=1

static func _draw_trim(canvas:CanvasItem,o:Vector2,alpha:float) -> void:
	var r:=TRIM
	_px(canvas,o,r.position.x,r.position.y,r.size.x,r.size.y,DEEP,alpha)
	_px(canvas,o,r.position.x,r.position.y,r.size.x,1,TEAL,alpha)
	# foam wave crests
	for x in range(r.position.x+1,r.position.x+r.size.x-3,6):
		_px(canvas,o,x,r.position.y+1,2,1,FOAM,alpha)
		_px(canvas,o,x+2,r.position.y+2,2,1,FOAM,alpha)
	# a tiny sail every so often
	for x in [r.position.x+11,r.position.x+23]:
		_px(canvas,o,x,r.position.y+1,1,2,SAIL,alpha)
		_px(canvas,o,x+1,r.position.y+2,1,1,SUN,alpha)
	_px(canvas,o,r.position.x,r.position.y,1,r.size.y,TEAL,alpha)
	_px(canvas,o,r.position.x+r.size.x-1,r.position.y,1,r.size.y,TEAL,alpha)

static func _draw_gull(canvas:CanvasItem,o:Vector2,alpha:float,frame:int) -> void:
	var x:=38
	var y:=13
	var wing:=SAIL
	if frame==0:
		_px(canvas,o,x,y,2,1,wing,alpha)
		_px(canvas,o,x+2,y+1,1,1,wing,alpha)
		_px(canvas,o,x+3,y,2,1,wing,alpha)
	else:
		_px(canvas,o,x,y+1,2,1,wing,alpha)
		_px(canvas,o,x+2,y,1,1,wing,alpha)
		_px(canvas,o,x+3,y+1,2,1,wing,alpha)
	_px(canvas,o,x+2,y+1 if frame==0 else y,1,1,SUN_EDGE,alpha)

## Gold star badge: shown once all three samples are served.
static func _draw_marker(canvas:CanvasItem,o:Vector2,alpha:float) -> void:
	var x:=29
	var y:=12
	_px(canvas,o,x+2,y,3,1,SUN_EDGE,alpha)
	_px(canvas,o,x+1,y+1,5,1,SUN_EDGE,alpha)
	_px(canvas,o,x,y+2,7,3,SUN_EDGE,alpha)
	_px(canvas,o,x+1,y+5,5,1,SUN_EDGE,alpha)
	_px(canvas,o,x+1,y+6,2,1,SUN_EDGE,alpha)
	_px(canvas,o,x+4,y+6,2,1,SUN_EDGE,alpha)
	_px(canvas,o,x+3,y+1,1,1,SUN,alpha)
	_px(canvas,o,x+2,y+2,3,3,SUN,alpha)
	_px(canvas,o,x+1,y+3,5,1,SUN,alpha)
	_px(canvas,o,x+2,y+5,3,1,SUN,alpha)
