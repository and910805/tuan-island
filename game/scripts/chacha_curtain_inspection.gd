extends Control

## T066 N04-2〈漏下來的一束光〉：貓空茶亭三幅遮簾的小插圖（不畫文字）。
##
## 掛在居民目標頁「檢查三處」按鈕的正上方；唯一的互動仍是那三顆既有按鈕。
## 這裡只讀 picks（0 靠山、1 中間、2 靠路），不處理輸入、不存檔、不改任何遊戲狀態。
## 每檢查一幅，那一幅才浮現各自的小線索，並掃過一道淡淡的光（約 0.9 秒後停止）。
## 減少動態：線索直接出現，沒有光掃動，也不啟用 _process。

const Curtain=preload("res://scripts/bamboo_curtain_art.gd")

const PANELS:=3
const HEIGHT:=118
const MIN_WIDTH:=360
const BEAM_H:=8
const BLIND_Y:=8
const BLIND_H:=72 # 竹簾圖 28x24 的整數 3 倍高
const FLOOR_Y:=80
const GAP:=8 # 簾與立柱之間的留白
const FLASH_TIME:=0.9

const WALL:=Color("3b2a1b")
const BEAM:=Color("5b3d27")
const BEAM_LIGHT:=Color("7a5233")
const BEAM_DARK:=Color("3f2a1a")
const POST:=Color("6b4a2f")
const POST_LIGHT:=Color("85603c")
const FLOOR:=Color("8a6a45")
const FLOOR_LINE:=Color("6e5236")
const FLOOR_EDGE:=Color("4e3924")
const HONEY:=Color("c9a05a")
const HONEY_DARK:=Color("8f6a35")
const CORD:=Color("8a4a2c")
const LIGHT:=Color("fff3c4")

var reduced:=true
var _seen:Array[int]=[]
var _flash:=-1
var _t:=0.0

static func make(reduced_motion:bool) -> Control:
	var art:=new()
	art.reduced=reduced_motion
	art.custom_minimum_size=Vector2(MIN_WIDTH,HEIGHT)
	art.size=Vector2(MIN_WIDTH,HEIGHT)
	art.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	art.clip_contents=true
	art.mouse_filter=Control.MOUSE_FILTER_IGNORE
	art.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	art.set_process(false)
	return art

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(_flash>=0 and not reduced)

## picks 是目前已檢查的順序（0 靠山、1 中間、2 靠路）。
## 新增剛好一幅時，只有那一幅播光；一次多幅（重新掛上畫面）直接顯示。
## 已檢查的幅數變少或被清掉（重來）就整個重置。
func sync(picks:Array) -> void:
	var now:Array[int]=[]
	for value in picks:
		var index:=int(value)
		if index>=0 and index<PANELS and not now.has(index):now.append(index)
	for index in _seen:
		if not now.has(index):
			reset()
			break
	var fresh:Array[int]=[]
	for index in now:
		if not _seen.has(index):fresh.append(index)
	for index in fresh:_seen.append(index)
	if fresh.size()==1 and not reduced:
		_flash=fresh[0]
		_t=0.0
		set_process(true)
	queue_redraw()

func reset() -> void:
	_seen.clear()
	_flash=-1
	_t=0.0
	set_process(false)
	queue_redraw()

func set_reduced_motion(value:bool) -> void:
	reduced=value
	if reduced:
		_flash=-1
		_t=0.0
		set_process(false)
	queue_redraw()

func inspected_count() -> int:
	return _seen.size()

func is_animating() -> bool:
	return _flash>=0

# 供自動化逐步推進；_process 走同一條路。
func advance(seconds:float) -> void:
	if _flash<0 or reduced:return
	_t+=maxf(0.0,seconds)
	if _t>=FLASH_TIME:
		_flash=-1
		_t=0.0
		set_process(false)
	queue_redraw()

func _process(delta:float) -> void:
	advance(delta)

# ------------------------------------------------------------------ 繪製 --

func _r(x:int,y:int,w:int,h:int,color:Color) -> void:
	if w<=0 or h<=0:return
	draw_rect(Rect2(x,y,w,h),color)

func _a(color:Color,k:float) -> Color:
	return Color(color.r,color.g,color.b,color.a*clampf(k,0.0,1.0))

func _width() -> int:
	return maxi(MIN_WIDTH,int(size.x))

func _slot() -> int:
	return floori(float(_width())/PANELS)

func _origin_x() -> int:
	return floori(float(_width()-_slot()*PANELS)*0.5)

func _blind(index:int) -> Rect2i:
	var slot:=_slot()
	return Rect2i(_origin_x()+index*slot+GAP,BLIND_Y,slot-GAP*2,BLIND_H)

# 該幅線索的顯示程度：沒檢查 0；正在播光的那幅隨光淡入；其餘 1。
func _reveal(index:int) -> float:
	if not _seen.has(index):return 0.0
	if index==_flash:return smoothstep(0.15,0.7,_t/FLASH_TIME)
	return 1.0

func _draw() -> void:
	var width:=_width()
	_r(0,0,width,HEIGHT,WALL)
	_draw_floor(width)
	for index in range(PANELS):
		var r:=_blind(index)
		_draw_view(index,r)
		var k:=_reveal(index)
		var tint:=Color(0.9,0.88,0.84,1.0).lerp(Color.WHITE,k)
		draw_texture_rect(Curtain.TEXTURE,Rect2(r),false,tint)
		if k<1.0:_r(r.position.x,r.position.y,r.size.x,r.size.y,Color(0.1,0.07,0.04,0.14*(1.0-k)))
	_draw_posts()
	_draw_beam(width)
	for index in range(PANELS):
		var r:=_blind(index)
		var k:=_reveal(index)
		if k<=0.0:continue
		_draw_clue(index,r,k)
	if _flash>=0:_draw_streak(_blind(_flash),_t/FLASH_TIME)

func _draw_floor(width:int) -> void:
	_r(0,FLOOR_Y,width,HEIGHT-FLOOR_Y,FLOOR)
	_r(0,FLOOR_Y,width,3,FLOOR_EDGE)
	var y:=FLOOR_Y+14
	while y<HEIGHT:
		_r(0,y,width,2,FLOOR_LINE)
		y+=14
	# 木板接縫錯開
	var row:=0
	y=FLOOR_Y+3
	while y<HEIGHT:
		var x:=(row%2)*30+12
		while x<width:
			_r(x,y,2,11,FLOOR_LINE)
			x+=60
		y+=14
		row+=1

func _draw_posts() -> void:
	var slot:=_slot()
	var ox:=_origin_x()
	for j in range(PANELS+1):
		var x:=ox+j*slot-(GAP>>1)
		_r(x,0,GAP,FLOOR_Y,POST)
		_r(x,0,2,FLOOR_Y,POST_LIGHT)
	# 兩側餘白也補上木牆
	_r(0,0,ox,FLOOR_Y,POST)
	_r(ox+slot*PANELS,0,_width()-ox-slot*PANELS,FLOOR_Y,POST)

func _draw_beam(width:int) -> void:
	_r(0,0,width,BEAM_H,BEAM)
	_r(0,0,width,2,BEAM_LIGHT)
	_r(0,BEAM_H-2,width,2,BEAM_DARK)
	# 掛簾的小鉤
	for index in range(PANELS):
		var r:=_blind(index)
		_r(r.position.x+4,BEAM_H,3,3,BEAM_DARK)
		_r(r.position.x+r.size.x-7,BEAM_H,3,3,BEAM_DARK)

# 簾後的風景：靠山是疊起的茶山、中間是一階階茶畦、靠路是一條小路。
func _draw_view(index:int,r:Rect2i) -> void:
	var x0:=r.position.x
	var y0:=r.position.y
	var w:=r.size.x
	var h:=r.size.y
	match index:
		0:
			_r(x0,y0,w,h,Color("b9d0c0"))
			var col:=0
			while col<w:
				var cw:=mini(8,w-col)
				var far:=12+int(absf(sin((col+5)*0.09))*18.0)
				_r(x0+col,y0+44-far,cw,h-(44-far),Color("8fb09a"))
				var near:=10+int(absf(sin((col+31)*0.13))*14.0)
				_r(x0+col,y0+60-near,cw,h-(60-near),Color("5f8a62"))
				col+=8
		1:
			_r(x0,y0,w,h,Color("e4dcb8"))
			for row in range(7):
				var c:=Color("6f8f4e") if row%2==0 else Color("5d7c42")
				_r(x0,y0+30+row*6,w,6,c)
			_r(x0,y0+30,w,3,Color("a9bf86"))
		_:
			_r(x0,y0,w,h,Color("cfd8d8"))
			_r(x0,y0+38,w,10,Color("9cb08c"))
			_r(x0,y0+48,w,h-48,Color("a39c8c"))
			_r(x0,y0+48,w,3,Color("7d776a"))
			var dash:=6
			while dash<w-12:
				_r(x0+dash,y0+62,12,3,Color("ebe4cc"))
				dash+=30
			_r(x0+w-24,y0+26,3,26,Color("4d3b2b"))
			_r(x0+w-30,y0+26,15,3,Color("4d3b2b"))

# 各自不同、看得出是真的物理線索：潮濕與落葉／缺一片竹與漏光／曬白與鬆脫。
func _draw_clue(index:int,r:Rect2i,k:float) -> void:
	var x0:=r.position.x
	var y0:=r.position.y
	var w:=r.size.x
	var h:=r.size.y
	var floor_glow:=Color(1.0,0.95,0.7,0.10)
	match index:
		0:
			# 靠山：山霧帶濕，簾腳發暗長苔，一道水痕，地上一片落葉和一小灘水
			_r(x0+3,y0+h-18,w-6,15,_a(Color(0.16,0.27,0.2,0.38),k))
			var step:=floori(float(w-24)/5.0)
			for n in range(6):
				_r(x0+8+n*step,y0+h-12+(n%2)*6,3,3,_a(Color("5f8f4a"),k))
			_r(x0+w-14,y0+30,3,30,_a(Color(0.2,0.22,0.16,0.35),k))
			var lx:=x0+int(w*0.3)
			_r(lx,FLOOR_Y+17,12,3,_a(Color("6f8a3c"),k))
			_r(lx+3,FLOOR_Y+14,6,3,_a(Color("86a04a"),k))
			_r(lx+3,FLOOR_Y+20,6,3,_a(Color("55702f"),k))
			_r(lx+12,FLOOR_Y+17,3,3,_a(Color("55702f"),k))
			_r(lx+30,FLOOR_Y+24,12,3,_a(Color(0.2,0.14,0.08,0.5),k))
			_r(x0+10,FLOOR_Y+4,w-20,20,_a(floor_glow,k*0.6))
		1:
			# 中間：少了一片竹，光從縫裡漏到地板；吊繩磨出毛邊，地上躺著那片竹
			var gy:=y0+30
			_r(x0+9,gy-3,w-18,3,_a(Color(1.0,0.9,0.6,0.35),k))
			_r(x0+9,gy,w-18,3,_a(LIGHT,k*0.95))
			_r(x0+9,gy+3,w-18,3,_a(Color(1.0,0.9,0.6,0.25),k))
			_r(x0+6,gy+3,3,12,_a(CORD,k))
			_r(x0+3,gy+15,3,3,_a(CORD,k))
			_r(x0+9,gy+12,3,3,_a(CORD,k))
			var half:=int(w*0.5)
			for row in range(5):
				_r(x0+14+row*6,FLOOR_Y+3+row*6,half,6,_a(Color(1.0,0.92,0.55,0.40-row*0.06),k))
			var sx:=x0+half+6
			_r(sx,FLOOR_Y+26,18,3,_a(HONEY,k))
			_r(sx+18,FLOOR_Y+26,3,3,_a(HONEY_DARK,k))
			_r(sx,FLOOR_Y+29,18,1,_a(HONEY_DARK,k))
		_:
			# 靠路：被太陽曬白的上緣、鬆開的繩結和翹起的簾腳，地上有灰塵與小石子
			for row in range(4):
				_r(x0+5,y0+8+row*9,w-10,3,_a(Color(1.0,0.96,0.8,0.30),k))
			_r(x0+w-9,y0+3,6,6,_a(Color("8a3b2a"),k))
			_r(x0+w-6,y0+9,3,6,_a(Color("8a3b2a"),k))
			_r(x0+w-15,y0+h,9,3,_a(HONEY_DARK,k))
			_r(x0+w-9,y0+h+3,6,3,_a(HONEY,k))
			for n in range(5):
				_r(x0+10+n*13,FLOOR_Y+14+(n*7)%12,3,3,_a(Color(0.85,0.78,0.62,0.7),k))
			_r(x0+w-30,FLOOR_Y+22,9,6,_a(Color("8c867a"),k))
			_r(x0+w-27,FLOOR_Y+19,6,3,_a(Color("b3ad9f"),k))
			_r(x0+10,FLOOR_Y+4,w-20,20,_a(floor_glow,k*0.6))

# 剛檢查的那一幅才有的一道斜斜的光；只跑一次。
func _draw_streak(r:Rect2i,p:float) -> void:
	var alpha:=sin(clampf(p,0.0,1.0)*PI)*0.5
	if alpha<=0.02:return
	var travel:=r.size.x+60
	var head:=int(snappedf(-30.0+travel*smoothstep(0.0,1.0,p),3.0))
	var left:=r.position.x
	var right:=r.position.x+r.size.x
	var row:=0
	while row<r.size.y:
		var cx:=left+head+int((r.size.y-row)*0.5)
		cx=int(snappedf(cx,3.0))
		var x0:=maxi(cx-9,left)
		var x1:=mini(cx+9,right)
		if x1>x0:_r(x0,r.position.y+row,x1-x0,3,Color(1.0,0.93,0.65,alpha*0.55))
		var c0:=maxi(cx-3,left)
		var c1:=mini(cx+3,right)
		if c1>c0:_r(c0,r.position.y+row,c1-c0,3,Color(1.0,0.97,0.8,alpha))
		row+=3
