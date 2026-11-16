@static_unload
extends RefCounted
## 第 40 章金瓜石「河邊淘砂金」的程式繪製圖（沒有新美術檔）。
##
## draw_site：淘砂處 SITE（山城西岸外的一格水面）上的小木板平台，從右邊的岸上伸到水面，
##  平台上放著一個圓形淺淘砂盤（深色金屬盤緣、盤裡是砂）；盤子左邊的水面有兩格交替的
##  漣漪（elapsed 驅動）。reduced motion 時固定畫第一格，與 elapsed 無關。
##  所有像素都在 BOUNDS（相對於水格左上角 `at`）之內：最多往右蓋到岸上 8 px、往上 8 px。
##
## pan_texture(stage)：面板用的 64×64 淘砂盤俯視圖（stage 0..5 各一張，快取）：
##  0 空盤；1 河砂堆上蓋著灰色石礫；2 滿滿的砂；3 砂少了、看得到一圈水；4 薄薄一層砂；
##  5 盤底黑砂，裡面幾點金光（金色像素只出現在 stage 5）。

const POINT:="gold_pan"
const BOUNDS:=Rect2(0,-8,40,40)
const PAN_SIZE:=64
const STAGES:=6

const OUTLINE:=Color("3a2a1a")
const WOOD:=Color("8a6238")
const WOOD_LIGHT:=Color("b88a55")
const WOOD_DARK:=Color("5c4026")
const POST:=Color("4e3620")
const WATER_SHADOW:=Color(0.05,0.16,0.18,0.35)
const RIPPLE:=Color("a8e0d6")
const RIPPLE_SOFT:=Color(0.66,0.88,0.84,0.6)
const RIM:=Color("4a4038")
const RIM_LIGHT:=Color("6e6256")
const METAL:=Color("8f8576")
const METAL_DARK:=Color("736a5d")
const SAND:=Color("d9c798")
const SAND_DARK:=Color("bfa977")
const SAND_LIGHT:=Color("ece0bc")
const STONE:=Color("8c8b86")
const STONE_LIGHT:=Color("b8b7b0")
const STONE_DARK:=Color("5e5d58")
const PAN_WATER:=Color("6fa9ae")
const PAN_WATER_LIGHT:=Color("9fd0cf")
const BLACK_SAND:=Color("2f2b29")
const BLACK_SAND_LIGHT:=Color("4b4642")
const GOLD:=Color("e9c44a")
const GOLD_LIGHT:=Color("f6e27a")

static var cache:Dictionary={}

# ------------------------------------------------------------------ world --

static func _box(canvas:CanvasItem,at:Vector2,x:float,y:float,w:float,h:float,c:Color) -> void:
	canvas.draw_rect(Rect2(at+Vector2(x,y),Vector2(w,h)),c)

## A pixel disc centred on (cx,cy) (local px), drawn as one rect per row.
static func _disc(canvas:CanvasItem,at:Vector2,cx:int,cy:int,rx:int,ry:int,c:Color) -> void:
	for dy in range(-ry,ry+1):
		var t:=1.0-float(dy*dy)/float(maxi(ry*ry,1))
		var half:=int(floorf(float(rx)*sqrt(maxf(t,0.0))+0.25))
		_box(canvas,at,cx-half,cy+dy,half*2+1,1,c)

## `at` = top-left of the water cell (camera-shifted). Platform from the bank (right)
## over the water, a pan resting on it, and (unless reduced) a two-frame ripple.
static func draw_site(canvas:CanvasItem,at:Vector2,elapsed:float,reduced:bool) -> void:
	var base:=at.round()
	# Shadow of the platform on the water.
	_box(canvas,base,9,23,31,3,WATER_SHADOW)
	# Posts standing in the water.
	_box(canvas,base,10,20,3,8,OUTLINE)
	_box(canvas,base,11,20,1,7,POST)
	_box(canvas,base,22,20,3,7,OUTLINE)
	_box(canvas,base,23,20,1,6,POST)
	# Plank deck x 9..40, y 7..22 (overlaps the bank by 8 px).
	_box(canvas,base,9,7,31,15,OUTLINE)
	var x:=10
	var i:=0
	while x<40:
		var w:=mini(5,40-x)
		_box(canvas,base,x,8,w,13,WOOD_LIGHT if i%2==0 else WOOD)
		_box(canvas,base,x,8,w,1,WOOD_LIGHT)
		_box(canvas,base,x,20,w,1,WOOD_DARK)
		if x+w<40:_box(canvas,base,x+w-1,8,1,13,WOOD_DARK)
		# Nail heads.
		_box(canvas,base,x+1,10,1,1,WOOD_DARK)
		_box(canvas,base,x+1,18,1,1,WOOD_DARK)
		x+=w
		i+=1
	# The panning pan resting on the deck (seen slightly from above).
	_disc(canvas,base,20,13,9,7,OUTLINE)
	_disc(canvas,base,20,13,8,6,RIM)
	_box(canvas,base,15,7,8,1,RIM_LIGHT)
	_disc(canvas,base,20,14,6,4,SAND_DARK)
	_disc(canvas,base,20,13,5,3,SAND)
	_box(canvas,base,17,12,3,1,SAND_LIGHT)
	_box(canvas,base,23,14,1,1,SAND_DARK)
	# Ripples on the open water left of the platform.
	var frame:=0 if reduced else (int(floorf(elapsed*2.0))%2+2)%2
	if frame==0:
		_box(canvas,base,2,12,5,1,RIPPLE)
		_box(canvas,base,3,13,3,1,RIPPLE_SOFT)
		_box(canvas,base,1,25,6,1,RIPPLE)
		_box(canvas,base,4,29,4,1,RIPPLE_SOFT)
	else:
		_box(canvas,base,1,14,6,1,RIPPLE)
		_box(canvas,base,2,15,4,1,RIPPLE_SOFT)
		_box(canvas,base,2,27,5,1,RIPPLE)
		_box(canvas,base,5,23,3,1,RIPPLE_SOFT)

# ------------------------------------------------------------------ panel --

static func _px(img:Image,x:int,y:int,c:Color) -> void:
	if x>=0 and y>=0 and x<img.get_width() and y<img.get_height():img.set_pixel(x,y,c)

static func _in(x:int,y:int,cx:float,cy:float,r:float) -> bool:
	var dx:=float(x)+0.5-cx
	var dy:=float(y)+0.5-cy
	return dx*dx+dy*dy<=r*r

static func _blob(img:Image,cx:int,cy:int,r:float,body:Color,light:Color,dark:Color) -> void:
	for y in range(cy-int(r)-1,cy+int(r)+2):
		for x in range(cx-int(r)-1,cx+int(r)+2):
			if not _in(x,y,float(cx)+0.5,float(cy)+0.5,r+0.6):continue
			var c:=body
			if not _in(x,y,float(cx)+0.5,float(cy)+0.5,r-0.4):c=dark
			elif x<cx and y<cy:c=light
			_px(img,x,y,c)

static func _paint_pan(img:Image,stage:int) -> void:
	var c:=float(PAN_SIZE)/2.0
	for y in PAN_SIZE:
		for x in PAN_SIZE:
			var col:=Color(0,0,0,0)
			if _in(x,y,c,c,31.0):col=OUTLINE
			if _in(x,y,c,c,30.0):col=RIM_LIGHT if (x+y)<52 else RIM
			if _in(x,y,c,c,27.0):
				col=METAL
				if not _in(x,y,c,c,26.0) or (not _in(x,y,c,c,14.0) and _in(x,y,c,c,15.0)):col=METAL_DARK
			match stage:
				1,2:
					if _in(x,y,c,c,25.0):
						col=SAND
						if (x*7+y*13)%11==0:col=SAND_DARK
						elif (x*5+y*3)%17==0:col=SAND_LIGHT
					if stage==1 and _in(x,y,c-2.0,c-2.0,18.0) and (x*3+y*7)%13==0:col=SAND_DARK
				3:
					if _in(x,y,c,c,25.0):
						col=PAN_WATER
						if (x*3+y*5)%19==0:col=PAN_WATER_LIGHT
					if _in(x,y,c+1.0,c+1.0,18.0):
						col=SAND
						if (x*7+y*13)%11==0:col=SAND_DARK
				4:
					if _in(x,y,c,c,25.0):
						col=PAN_WATER
						if (x*3+y*5)%19==0:col=PAN_WATER_LIGHT
					if _in(x,y,c+2.0,c+2.0,11.0):
						col=SAND if (x+y)%5!=0 else METAL
						if (x*7+y*13)%11==0:col=SAND_DARK
				5:
					if _in(x,y,c,c,25.0):
						col=PAN_WATER
						if (x*3+y*5)%19==0:col=PAN_WATER_LIGHT
					if _in(x,y,c+2.0,c+2.0,9.0):
						col=BLACK_SAND if (x*5+y*7)%6!=0 else BLACK_SAND_LIGHT
			img.set_pixel(x,y,col)
	if stage==1:
		_blob(img,24,26,3.0,STONE,STONE_LIGHT,STONE_DARK)
		_blob(img,38,24,2.5,STONE,STONE_LIGHT,STONE_DARK)
		_blob(img,30,38,3.5,STONE,STONE_LIGHT,STONE_DARK)
		_blob(img,41,36,2.0,STONE,STONE_LIGHT,STONE_DARK)
	if stage==5:
		for p:Vector2i in [Vector2i(31,32),Vector2i(35,35),Vector2i(29,37),Vector2i(37,31)]:
			_px(img,p.x,p.y,GOLD)
		for p:Vector2i in [Vector2i(32,32),Vector2i(35,34),Vector2i(30,37)]:
			_px(img,p.x,p.y,GOLD_LIGHT)

static func pan_image(stage:int) -> Image:
	var key:=clampi(stage,0,STAGES-1)
	var img:=Image.create_empty(PAN_SIZE,PAN_SIZE,false,Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	_paint_pan(img,key)
	return img

static func pan_texture(stage:int) -> Texture2D:
	var key:=clampi(stage,0,STAGES-1)
	if cache.has(key):return cache[key]
	var tex:=ImageTexture.create_from_image(pan_image(key))
	cache[key]=tex
	return tex
