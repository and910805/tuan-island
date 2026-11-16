@static_unload
extends RefCounted
## 第 40 章金瓜石「運礦路線」的程式繪製圖（沒有新美術檔；範本 gold_panning_art.gd）。
##
## draw_track(canvas,at,cell)：一格台車軌道（俯視）。底下一條碎石道床、木枕、兩條深色鐵軌。
##  形狀由 track_shape(cell)（看 Route.TRACK 的前後格）決定：直線 h／v、四種轉角（以相連的兩個方向命名，
##  弧心在那兩個方向夾住的格角）、端點 end_*（以相連方向命名；封閉的那一側有一根紅色擋木）。
##  所有形狀用同一組橫向位置：道床 5..26、木枕 7..24、鐵軌 10..11 與 20..21（轉角用到弧心的距離換算），
##  所以相鄰格的鐵軌在格邊一定接得上。像素都在 TRACK_BOUNDS（整格 0..31）之內。
##
## draw_platform(canvas,at,kind)：
##  "load"（Route.STOPS[0]，坑口下方）：兩根木柱（x -4..-1、32..35，y -18..29）撐一根橫梁（y -20..-17），
##   梁下吊著漏斗（y -15..-8）與出料口（y -7..-4），全部在格子上方與上緣，不蓋住台車車身。
##  "unload"（Route.STOPS[-1]，接駁站旁）：格子左上方的矮木箱（x -4..15，y -16..-1）、從台車那側斜向木箱的
##   斜槽（x 16..29，y -12..0），以及右上角的小木牌（x 24..35，y -20..-13，牌上畫著小台車；柱子 y -13..1）。
##  像素都在 PLATFORM_BOUNDS 之內；平台不用台車、礦料、銅、金的顏色。
##
## draw_cart(canvas,at,loaded,elapsed,reduced)：側面的木製台車（車身 x 2..29，y 3..21；鐵輪 y 20..28；
##  影子 y 27..28）。loaded 時車斗裡有一堆礦料（x 4..28，y -5..7；灰石色加幾點銅色與金色）；
##  loaded 且非 reduced 時礦料上有兩格交替的閃光（elapsed 驅動，y -2..5）。
##  空車或 reduced 時畫面與 elapsed 無關。像素都在 CART_BOUNDS 之內。
##
## cart_texture(loaded)：面板用的 64×64 台車（快取）；金色／銅色像素只出現在 loaded。

const Route=preload("res://scripts/ore_route.gd")
const POINT:="ore_cart"
const TRACK_BOUNDS:=Rect2(0,0,32,32)
const PLATFORM_BOUNDS:=Rect2(-4,-20,40,52)
const CART_BOUNDS:=Rect2(-2,-10,36,42)
const CART_SIZE:=64
const CELL:=32
const SHAPES:=["h","v","ne","nw","se","sw","end_n","end_s","end_e","end_w"]
const DIRS:={Vector2i(0,-1):"n",Vector2i(0,1):"s",Vector2i(1,0):"e",Vector2i(-1,0):"w"}
## 橫向位置（直線格的列／行；轉角格換算成到弧心的距離）。
const RAIL_LINES:=[10,11,20,21]
const TIE_SPAN:=Vector2i(7,24)
const BED_SPAN:=Vector2i(5,26)

# 軌道
const BALLAST:=Color("9a9286")
const BALLAST_DARK:=Color("6f685e")
const BALLAST_LIGHT:=Color("bdb5a6")
const TIE:=Color("7a5232")
const TIE_DARK:=Color("4f3420")
const RAIL:=Color("34343a")
const RAIL_LIGHT:=Color("74747c")
const BUFFER:=Color("a8452e")
const BUFFER_DARK:=Color("5e2418")
const BUFFER_LIGHT:=Color("d0694a")
# 裝礦台／卸礦台
const FRAME:=Color("8c6a44")
const FRAME_LIGHT:=Color("b28c5c")
const FRAME_DARK:=Color("4a3320")
const BIN_INSIDE:=Color("2e241c")
const BIN_PEBBLE:=Color("5b5249")
const SIGN_MARK:=Color("463226")
# 台車
const OUTLINE:=Color("3a2a1a")
const WOOD:=Color("9a6a3a")
const WOOD_LIGHT:=Color("c4925a")
const WOOD_DARK:=Color("5e3f22")
const IRON:=Color("2c2b30")
const IRON_LIGHT:=Color("5c5a62")
const SHADOW:=Color(0.0,0.0,0.0,0.22)
# 礦料
const ORE:=Color("85827c")
const ORE_LIGHT:=Color("b0ada5")
const ORE_DARK:=Color("57544f")
const COPPER:=Color("c46a32")
const GOLD:=Color("e9c44a")
const GOLD_LIGHT:=Color("f6e27a")
const GLINT:=Color("fff3b8")
const GLINT_CORE:=Color("ffffff")

## 軌道遮罩的代碼 → 顏色（0 = 透明，不畫）。
const TRACK_COLORS:=[Color(0,0,0,0),BALLAST,BALLAST_DARK,BALLAST_LIGHT,TIE,TIE_DARK,RAIL,RAIL_LIGHT,BUFFER,BUFFER_DARK,BUFFER_LIGHT]
const C_BALLAST:=1
const C_BALLAST_DARK:=2
const C_BALLAST_LIGHT:=3
const C_TIE:=4
const C_TIE_DARK:=5
const C_RAIL:=6
const C_RAIL_LIGHT:=7
const C_BUFFER:=8
const C_BUFFER_DARK:=9
const C_BUFFER_LIGHT:=10

static var track_cache:Dictionary={}
static var cart_cache:Dictionary={}

# ------------------------------------------------------------------ helpers --

static func _box(canvas:CanvasItem,at:Vector2,x:float,y:float,w:float,h:float,c:Color) -> void:
	canvas.draw_rect(Rect2(at+Vector2(x,y),Vector2(w,h)),c)

## A pixel disc centred on (cx,cy) (local px), drawn as one rect per row.
static func _disc(canvas:CanvasItem,at:Vector2,cx:int,cy:int,rx:int,ry:int,c:Color) -> void:
	for dy in range(-ry,ry+1):
		var t:=1.0-float(dy*dy)/float(maxi(ry*ry,1))
		var half:=int(floorf(float(rx)*sqrt(maxf(t,0.0))+0.25))
		_box(canvas,at,cx-half,cy+dy,half*2+1,1,c)

# ------------------------------------------------------------------ track --

## "h"／"v"／"ne"／"nw"／"se"／"sw"／"end_n"／"end_s"／"end_e"／"end_w"／""（不在軌道上）。
static func track_shape(cell:Vector2i) -> String:
	var i:int=Route.TRACK.find(cell)
	if i<0:return ""
	var links:Array[String]=[]
	for j:int in [i-1,i+1]:
		if j<0 or j>=Route.TRACK.size():continue
		var other:Vector2i=Route.TRACK[j]
		var step:Vector2i=other-cell
		if DIRS.has(step):
			var dir:String=DIRS[step]
			if not links.has(dir):links.append(dir)
	if links.size()==1:return "end_"+links[0]
	if links.size()!=2:return ""
	var n:=links.has("n")
	var s:=links.has("s")
	var e:=links.has("e")
	var w:=links.has("w")
	if n and s:return "v"
	if e and w:return "h"
	return ("n" if n else "s")+("e" if e else "w")

static func _ballast_code(x:int,y:int,edge:bool) -> int:
	if edge or (x*7+y*13)%11==0:return C_BALLAST_DARK
	if (x*5+y*3)%13==0:return C_BALLAST_LIGHT
	return C_BALLAST

## Straight / end cell in "along" (a) and "across" (c) coordinates. For ends, a=0 is the closed side.
static func _straight_code(a:int,c:int,is_end:bool,x:int,y:int) -> int:
	if is_end:
		if a>=2 and a<=6 and c>=6 and c<=25:
			if a==2 or a==6 or c==6 or c==25:return C_BUFFER_DARK
			if a==4 and c in RAIL_LINES:return C_BUFFER_DARK
			return C_BUFFER_LIGHT if a==3 else C_BUFFER
		if a<1:return 0
	if not is_end or a>=5:
		if c==10 or c==21:return C_RAIL_LIGHT
		if c==11 or c==20:return C_RAIL
	var phase:=posmod(a,8)
	if c>=TIE_SPAN.x and c<=TIE_SPAN.y and phase>=2 and phase<=5 and (not is_end or a>=8):
		return C_TIE_DARK if c==TIE_SPAN.x or c==TIE_SPAN.y else C_TIE
	if c>=BED_SPAN.x and c<=BED_SPAN.y:return _ballast_code(x,y,c==BED_SPAN.x or c==BED_SPAN.y)
	return 0

## Corner cell: rings around the cell corner (cx,cy) shared by the two linked sides.
static func _corner_code(x:int,y:int,cx:int,cy:int) -> int:
	var vx:=absf(float(x)+0.5-float(cx))
	var vy:=absf(float(y)+0.5-float(cy))
	var d:=sqrt(vx*vx+vy*vy)
	if (d>=10.0 and d<11.0) or (d>=21.0 and d<22.0):return C_RAIL_LIGHT
	if (d>=11.0 and d<12.0) or (d>=20.0 and d<21.0):return C_RAIL
	if d>=7.0 and d<25.0:
		var angle:=atan2(vy,vx)
		for k in 4:
			var phi:=(float(k)+0.5)*PI/8.0
			if absf(d*sin(angle-phi))<=1.6:return C_TIE_DARK if d<8.0 or d>=24.0 else C_TIE
	if d>=5.0 and d<27.0:return _ballast_code(x,y,d<6.0 or d>=26.0)
	return 0

static func _track_code(shape:String,x:int,y:int) -> int:
	match shape:
		"h":return _straight_code(x,y,false,x,y)
		"v":return _straight_code(y,x,false,x,y)
		"end_e":return _straight_code(x,y,true,x,y)
		"end_w":return _straight_code(CELL-1-x,y,true,x,y)
		"end_s":return _straight_code(y,x,true,x,y)
		"end_n":return _straight_code(CELL-1-y,x,true,x,y)
		"ne":return _corner_code(x,y,CELL,0)
		"nw":return _corner_code(x,y,0,0)
		"se":return _corner_code(x,y,CELL,CELL)
		"sw":return _corner_code(x,y,0,CELL)
	return 0

## The colour of local pixel (x,y) of a track shape (transparent outside the track).
static func track_pixel(shape:String,x:int,y:int) -> Color:
	return TRACK_COLORS[_track_code(shape,x,y)]

## Non-overlapping [x,y,w,h,code] rects covering one shape (row runs merged downwards), cached.
static func _track_rects(shape:String) -> Array:
	if track_cache.has(shape):return track_cache[shape]
	var rects:Array=[]
	var open:Dictionary={}
	for y in CELL:
		var next_open:Dictionary={}
		var x:=0
		while x<CELL:
			var code:=_track_code(shape,x,y)
			var w:=1
			while x+w<CELL and _track_code(shape,x+w,y)==code:w+=1
			if code!=0:
				var key:=Vector3i(x,w,code)
				if open.has(key):
					var index:int=open[key]
					var rect:Array=rects[index]
					rect[3]=int(rect[3])+1
					next_open[key]=index
				else:
					rects.append([x,y,w,1,code])
					next_open[key]=rects.size()-1
			x+=w
		open=next_open
	track_cache[shape]=rects
	return rects

## `at` = top-left of the cell (camera-shifted). Nothing is drawn for cells off Route.TRACK.
static func draw_track(canvas:CanvasItem,at:Vector2,cell:Vector2i) -> void:
	var shape:=track_shape(cell)
	if shape.is_empty():return
	var base:=at.round()
	for rect:Array in _track_rects(shape):
		var c:Color=TRACK_COLORS[int(rect[4])]
		canvas.draw_rect(Rect2(base+Vector2(float(rect[0]),float(rect[1])),Vector2(float(rect[2]),float(rect[3]))),c)

# --------------------------------------------------------------- platforms --

static func draw_platform(canvas:CanvasItem,at:Vector2,kind:String) -> void:
	var base:=at.round()
	match kind:
		"load":_draw_load(canvas,base)
		"unload":_draw_unload(canvas,base)

## Mine-mouth loading frame: posts beside the cell, beam and hopper above it.
static func _draw_load(canvas:CanvasItem,b:Vector2) -> void:
	# Posts (left x -4..-1, right x 32..35), y -18..29.
	_box(canvas,b,-4,-18,4,48,FRAME_DARK)
	_box(canvas,b,-3,-17,2,46,FRAME)
	_box(canvas,b,-3,-17,1,46,FRAME_LIGHT)
	_box(canvas,b,32,-18,4,48,FRAME_DARK)
	_box(canvas,b,33,-17,2,46,FRAME)
	_box(canvas,b,33,-17,1,46,FRAME_LIGHT)
	# Top beam y -20..-17.
	_box(canvas,b,-4,-20,40,4,FRAME_DARK)
	_box(canvas,b,-3,-19,38,1,FRAME_LIGHT)
	_box(canvas,b,-3,-18,38,1,FRAME)
	# Knee braces.
	for i in 5:
		_box(canvas,b,i,-12-i,2,1,FRAME_DARK)
		_box(canvas,b,30-i,-12-i,2,1,FRAME_DARK)
	# Hangers.
	_box(canvas,b,7,-16,1,1,FRAME_DARK)
	_box(canvas,b,24,-16,1,1,FRAME_DARK)
	# Hopper y -15..-8, narrowing downwards.
	for r in 8:
		var left:=5+r
		var w:=22-2*r
		var y:=-15+r
		if r==0 or r==7:
			_box(canvas,b,left,y,w,1,FRAME_DARK)
			continue
		var c:=FRAME
		if r==1:c=BIN_INSIDE
		elif r==2:c=FRAME_LIGHT
		elif r==5:c=FRAME_DARK
		_box(canvas,b,left,y,w,1,FRAME_DARK)
		_box(canvas,b,left+1,y,w-2,1,c)
	# Spout y -7..-4 (the loaded ore heap is drawn over its tip).
	_box(canvas,b,13,-7,6,4,FRAME_DARK)
	_box(canvas,b,14,-7,4,3,FRAME_LIGHT)
	_box(canvas,b,15,-7,1,3,FRAME)

## Shuttle-stop unloading: low bin up-left, a chute from the cart side, and a small sign.
static func _draw_unload(canvas:CanvasItem,b:Vector2) -> void:
	# Bin x -4..15, y -16..-1.
	_box(canvas,b,-4,-16,20,16,FRAME_DARK)
	_box(canvas,b,-3,-15,18,1,FRAME_LIGHT)
	_box(canvas,b,-3,-14,18,3,BIN_INSIDE)
	for p:Vector2i in [Vector2i(0,-13),Vector2i(4,-12),Vector2i(7,-14),Vector2i(11,-13),Vector2i(2,-14)]:
		_box(canvas,b,p.x,p.y,2,1,BIN_PEBBLE)
	# Front boards y -10..-2 (row -11 and -1 stay dark).
	var x:=-3
	var i:=0
	while x<15:
		var w:=mini(4,15-x)
		_box(canvas,b,x,-10,w,9,FRAME_LIGHT if i%2==0 else FRAME)
		if x+w<15:_box(canvas,b,x+w-1,-10,1,9,FRAME_DARK)
		x+=w
		i+=1
	# Chute from the cart side (x 26..29, y -2..0) up-left to the bin (x 16..19, y -12..-10).
	for k in 6:
		_box(canvas,b,26-2*k,-2-2*k,4,3,FRAME_DARK)
	for k in 6:
		_box(canvas,b,27-2*k,-1-2*k,2,1,FRAME_LIGHT)
	# Sign: post x 31..32, y -13..1; board x 24..35, y -20..-13 with a little cart.
	_box(canvas,b,31,-13,2,15,FRAME_DARK)
	_box(canvas,b,24,-20,12,8,FRAME_DARK)
	_box(canvas,b,25,-19,10,6,FRAME_LIGHT)
	_box(canvas,b,27,-18,6,2,SIGN_MARK)
	_box(canvas,b,28,-16,1,1,SIGN_MARK)
	_box(canvas,b,31,-16,1,1,SIGN_MARK)

# -------------------------------------------------------------------- cart --

static func _glint_frame(elapsed:float) -> int:
	return (int(floorf(elapsed*2.0))%2+2)%2

## `at` = top-left of the cart's cell. Side view of the cart sitting on the rails.
static func draw_cart(canvas:CanvasItem,at:Vector2,loaded:bool,elapsed:float,reduced:bool) -> void:
	var b:=at.round()
	# Ground shadow y 27..28.
	_box(canvas,b,2,27,28,2,SHADOW)
	# Open top: back rim (y 3..4) and the inside wall (y 5..6).
	_box(canvas,b,3,3,26,1,OUTLINE)
	_box(canvas,b,2,4,1,3,OUTLINE)
	_box(canvas,b,29,4,1,3,OUTLINE)
	_box(canvas,b,3,4,26,1,WOOD)
	_box(canvas,b,3,5,26,2,WOOD_DARK)
	if loaded:_draw_heap(canvas,b)
	# Body y 7..21, slightly narrower towards the bottom.
	for y in range(7,22):
		var inset:=floori(float(y-7)/5.0)
		var left:=2+inset
		var w:=28-2*inset
		_box(canvas,b,left,y,w,1,OUTLINE)
		if y==7 or y==21:continue
		var c:=WOOD
		if y==8:c=WOOD_LIGHT
		elif y==13 or y==17:c=WOOD_DARK
		_box(canvas,b,left+1,y,w-2,1,c)
	# Iron straps and bolts.
	_box(canvas,b,7,8,2,13,IRON)
	_box(canvas,b,23,8,2,13,IRON)
	for p:Vector2i in [Vector2i(8,11),Vector2i(8,16),Vector2i(23,11),Vector2i(23,16)]:
		_box(canvas,b,p.x,p.y,1,1,IRON_LIGHT)
	# Axle and wheels (y 20..28).
	_box(canvas,b,6,22,20,1,IRON)
	for cx:int in [9,23]:
		_disc(canvas,b,cx,24,4,4,IRON)
		_box(canvas,b,cx-1,23,3,3,IRON_LIGHT)
		_box(canvas,b,cx,24,1,1,IRON)
	if loaded and not reduced:
		if _glint_frame(elapsed)==0:
			_box(canvas,b,12,-2,1,5,GLINT)
			_box(canvas,b,10,0,5,1,GLINT)
			_box(canvas,b,12,0,1,1,GLINT_CORE)
		else:
			_box(canvas,b,20,1,1,5,GLINT)
			_box(canvas,b,18,3,5,1,GLINT)
			_box(canvas,b,20,3,1,1,GLINT_CORE)

## Ore heap in the cart, rows y -5..7 (the body's front rim covers row 7).
static func _draw_heap(canvas:CanvasItem,b:Vector2) -> void:
	for y in range(-5,8):
		var dy:=y-8
		var half:=int(floorf(12.0*sqrt(maxf(1.0-float(dy*dy)/169.0,0.0))+0.25))
		var left:=16-half
		var w:=half*2+1
		if y==-5:
			_box(canvas,b,left,y,w,1,ORE_DARK)
			continue
		_box(canvas,b,left,y,w,1,ORE)
		_box(canvas,b,left,y,1,1,ORE_DARK)
		_box(canvas,b,left+w-1,y,1,1,ORE_DARK)
		for x in range(left+1,left+w-1):
			if (x*7+y*11)%9==0:_box(canvas,b,x,y,1,1,ORE_DARK)
			elif (x*3+y*5)%7==0:_box(canvas,b,x,y,1,1,ORE_LIGHT)
	for p:Vector2i in [Vector2i(11,2),Vector2i(19,-1),Vector2i(22,4),Vector2i(14,5)]:
		_box(canvas,b,p.x,p.y,1,1,COPPER)
	for p:Vector2i in [Vector2i(16,0),Vector2i(9,5),Vector2i(20,3)]:
		_box(canvas,b,p.x,p.y,1,1,GOLD)
	_box(canvas,b,16,-1,1,1,GOLD_LIGHT)

# ------------------------------------------------------------------- panel --

static func _px(img:Image,x:int,y:int,c:Color) -> void:
	if x>=0 and y>=0 and x<img.get_width() and y<img.get_height():img.set_pixel(x,y,c)

static func _fill(img:Image,x:int,y:int,w:int,h:int,c:Color) -> void:
	for yy in range(y,y+h):
		for xx in range(x,x+w):
			_px(img,xx,yy,c)

static func _in(x:int,y:int,cx:float,cy:float,r:float) -> bool:
	var dx:=float(x)+0.5-cx
	var dy:=float(y)+0.5-cy
	return dx*dx+dy*dy<=r*r

static func _stone(img:Image,cx:int,cy:int,r:float) -> void:
	for y in range(cy-int(r)-1,cy+int(r)+2):
		for x in range(cx-int(r)-1,cx+int(r)+2):
			if not _in(x,y,float(cx)+0.5,float(cy)+0.5,r+0.6):continue
			var c:=ORE
			if not _in(x,y,float(cx)+0.5,float(cy)+0.5,r-0.4):c=ORE_DARK
			elif x<cx and y<cy:c=ORE_LIGHT
			_px(img,x,y,c)

static func _wheel(img:Image,cx:int,cy:int) -> void:
	var fx:=float(cx)+0.5
	var fy:=float(cy)+0.5
	for y in range(cy-8,cy+9):
		for x in range(cx-8,cx+9):
			if not _in(x,y,fx,fy,7.2):continue
			var c:=OUTLINE
			if _in(x,y,fx,fy,6.2):
				c=IRON
				if not _in(x,y,fx,fy,5.2) and x<cx and y<cy:c=IRON_LIGHT
				elif _in(x,y,fx,fy,3.5) and not _in(x,y,fx,fy,2.5):c=IRON_LIGHT
				elif _in(x,y,fx,fy,1.2):c=IRON_LIGHT
			_px(img,x,y,c)

static func _paint_cart(img:Image,loaded:bool) -> void:
	# Ground shadow.
	_fill(img,8,57,48,3,SHADOW)
	# Open top: back rim and inside wall (y 9..15).
	_fill(img,5,9,54,1,OUTLINE)
	_fill(img,4,10,1,6,OUTLINE)
	_fill(img,59,10,1,6,OUTLINE)
	_fill(img,5,10,54,2,WOOD)
	_fill(img,5,12,54,4,WOOD_DARK)
	if loaded:
		# Ore heap y 2..17.
		for y in range(2,18):
			var dy:=y-17
			var half:=int(floorf(26.0*sqrt(maxf(1.0-float(dy*dy)/225.0,0.0))+0.25))
			for x in range(32-half,32+half):
				var c:=ORE
				if y==2 or x==32-half or x==31+half:c=ORE_DARK
				elif (x*7+y*11)%9==0:c=ORE_DARK
				elif (x*3+y*5)%7==0:c=ORE_LIGHT
				_px(img,x,y,c)
		_stone(img,22,10,3.0)
		_stone(img,38,7,3.5)
		_stone(img,46,13,2.5)
		_stone(img,30,14,2.5)
		_stone(img,15,14,2.0)
		for p:Vector2i in [Vector2i(26,6),Vector2i(41,12),Vector2i(18,11)]:
			_fill(img,p.x,p.y,2,2,COPPER)
		for p:Vector2i in [Vector2i(33,9),Vector2i(24,14)]:
			_fill(img,p.x,p.y,2,2,GOLD)
			_px(img,p.x,p.y,GOLD_LIGHT)
		_px(img,44,8,GOLD)
		_px(img,35,4,GOLD)
	else:
		# Empty: the back planks of the inside are visible.
		for x:int in [14,23,32,41,50]:
			_fill(img,x,12,1,4,OUTLINE)
		_fill(img,5,15,54,1,OUTLINE)
	# Body y 16..45, narrowing towards the bottom.
	for y in range(16,46):
		var inset:=floori(float(y-16)/6.0)
		var left:=3+inset
		var w:=58-2*inset
		_fill(img,left,y,w,1,OUTLINE)
		if y==16 or y==45:continue
		var c:=WOOD
		if y<=18:c=WOOD_LIGHT
		elif y==19 or y==29 or y==37:c=WOOD_DARK
		elif y==20 or y==30 or y==38:c=WOOD_LIGHT
		_fill(img,left+1,y,w-2,1,c)
	# Iron straps and bolts.
	for sx:int in [14,47]:
		_fill(img,sx,17,3,28,IRON)
		_fill(img,sx,17,1,28,IRON_LIGHT)
		for by:int in [23,32,41]:
			_px(img,sx+1,by,IRON_LIGHT)
	# Axle and wheels.
	_fill(img,10,46,44,2,IRON)
	_wheel(img,18,50)
	_wheel(img,45,50)

static func cart_image(loaded:bool) -> Image:
	var img:=Image.create_empty(CART_SIZE,CART_SIZE,false,Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	_paint_cart(img,loaded)
	return img

static func cart_texture(loaded:bool) -> Texture2D:
	if cart_cache.has(loaded):return cart_cache[loaded]
	var tex:=ImageTexture.create_from_image(cart_image(loaded))
	cart_cache[loaded]=tex
	return tex
